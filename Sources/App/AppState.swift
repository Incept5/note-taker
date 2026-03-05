import SwiftUI
import Combine
import AppKit
import OSLog

/// Centralized app state tying together process discovery, audio capture, and UI phase.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date, liveText: String)
        case stopped(CapturedAudio)
        case transcribing(CapturedAudio, progress: Double)
        case transcribed(CapturedAudio, MeetingTranscription)
        case summarizing(CapturedAudio, MeetingTranscription)
        case summarized(CapturedAudio, MeetingTranscription, MeetingSummary)
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): true
            case (.recording(let a, let ta), .recording(let b, let tb)):
                a == b && ta == tb
            case (.stopped(let a), .stopped(let b)): a.directory == b.directory
            case (.transcribing(let a, _), .transcribing(let b, _)): a.directory == b.directory
            case (.transcribed(let a, _), .transcribed(let b, _)): a.directory == b.directory
            case (.summarizing(let a, _), .summarizing(let b, _)): a.directory == b.directory
            case (.summarized(let a, _, _), .summarized(let b, _, _)): a.directory == b.directory
            case (.error(let a), .error(let b)): a == b
            default: false
            }
        }
    }

    enum NavigationDestination: Equatable {
        case none
        case history
        case meetingDetail(MeetingRecord)

        static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
            switch (lhs, rhs) {
            case (.none, .none): true
            case (.history, .history): true
            case (.meetingDetail(let a), .meetingDetail(let b)): a.id == b.id
            default: false
            }
        }

        var isMeetingDetail: Bool {
            if case .meetingDetail = self { return true }
            return false
        }
    }

    @Published var phase: Phase = .idle
    @Published var showingOnboarding = false
    @Published var showingModelPicker = false
    @Published var navigation: NavigationDestination = .none

    @Published var summarizationBackend: String {
        didSet {
            UserDefaults.standard.set(summarizationBackend, forKey: "summarizationBackend")
        }
    }

    @Published var selectedMLXModel: String? {
        didSet {
            if let model = selectedMLXModel {
                UserDefaults.standard.set(model, forKey: "selectedMLXModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedMLXModel")
            }
        }
    }

    @Published var selectedOllamaModel: String? {
        didSet {
            if let model = selectedOllamaModel {
                UserDefaults.standard.set(model, forKey: "selectedOllamaModel")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedOllamaModel")
            }
        }
    }

    @Published var micEnabled: Bool {
        didSet {
            UserDefaults.standard.set(micEnabled, forKey: "micEnabled")
        }
    }

    /// Gain multiplier for mic audio in the recording (1.0 = unity, higher = louder).
    @Published var micGain: Float {
        didSet {
            UserDefaults.standard.set(micGain, forKey: "micGain")
        }
    }

    @Published var autoRecordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoRecordEnabled, forKey: "autoRecordEnabled")
        }
    }

    @Published var calendarAutoRecordEnabled: Bool {
        didSet {
            UserDefaults.standard.set(calendarAutoRecordEnabled, forKey: "calendarAutoRecordEnabled")
        }
    }

    /// Number of days to retain audio recording files. Older recordings are deleted on launch.
    @Published var recordingRetentionDays: Int {
        didSet {
            UserDefaults.standard.set(recordingRetentionDays, forKey: "recordingRetentionDays")
        }
    }

    @Published var speechRecognitionOnDeviceOnly: Bool {
        didSet {
            UserDefaults.standard.set(speechRecognitionOnDeviceOnly, forKey: "speechRecognitionOnDeviceOnly")
        }
    }

    @Published var ollamaServerURL: String {
        didSet {
            UserDefaults.standard.set(ollamaServerURL, forKey: "ollamaServerURL")
            summarizationService.updateBaseURL(ollamaServerURL)
        }
    }

    /// Custom system prompt for summarization. When nil or empty, the default built-in prompt is used.
    /// Persisted manually via `setCustomSystemPrompt(_:)` to avoid @Published didSet init bugs.
    @Published var customSystemPrompt: String?

    func setCustomSystemPrompt(_ prompt: String?) {
        let trimmed = prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            customSystemPrompt = trimmed
            UserDefaults.standard.set(trimmed, forKey: "customSystemPrompt")
        } else {
            customSystemPrompt = nil
            UserDefaults.standard.removeObject(forKey: "customSystemPrompt")
        }
    }

    let captureService = AudioCaptureService()
    let audioDeviceManager = AudioDeviceManager()
    let modelManager: ModelManager
    let mlxModelManager: MLXModelManager
    let transcriptionService: TranscriptionService
    let summarizationService: SummarizationService
    let meetingStore: MeetingStore

    /// Callback for opening a meeting in the result window (set by AppDelegate).
    var onShowResultWindow: ((MeetingSummary, String, String) -> Void)?

    /// Callback for opening the settings window (set by AppDelegate).
    var onOpenSettings: (() -> Void)?

    /// Callback for opening the history window (set by AppDelegate).
    var onOpenHistory: (() -> Void)?

    let calendarService = CalendarService()
    let googleAuthService = GoogleCalendarAuthService()

    @Published var googleCalendarEmail: String?

    private enum AutoRecordTrigger {
        case meetingApp(String)       // Zoom/Teams process launched
        case calendarEvent(String)    // calendar event title
    }

    private var currentMeetingId: String?
    private var currentMeetingParticipants: [String]?
    private var currentMeetingCalendarEndTime: Date?
    private var speechTranscriber: SpeechStreamingTranscriber?
    /// Append-only transcript buffer built during recording. Each entry is a chunk of text
    /// with a timestamp, committed whenever we detect SFSpeech text shrinking (session reset)
    /// or at recording stop. Text only grows — never deleted, never overwritten.
    private var liveTranscriptSegments: [TranscriptSegment] = []
    /// Text from the current SFSpeech "window" — committed to liveTranscriptSegments when
    /// we detect a text shrink (SFSpeech reset) or when recording stops.
    private var currentChunkText: String = ""
    /// Length of text from the previous callback — used to detect shrinks.
    private var lastCallbackTextLength: Int = 0
    /// Wall-clock time when the current chunk started.
    private var currentChunkStartDate: Date = .now
    /// When the current recording started.
    private var liveTextRecordingStart: Date = .now
    /// Tracks what triggered an auto-started recording (nil for manual recordings).
    private var autoRecordTrigger: AutoRecordTrigger?
    /// Timer for monitoring audio silence during auto-recordings.
    private var silenceTimer: Timer?
    /// Timer that fires when a calendar event's scheduled end time passes (+ grace period).
    private var calendarEndTimer: Timer?
    /// Rolling window of recent audio samples (true = silent, false = audible).
    private var silenceWindow: [Bool] = []
    /// Seconds elapsed since silence monitoring started (negative = grace period).
    private var silenceMonitorElapsed: Int = 0
    /// Timer for detecting meeting audio before starting a recording.
    private var meetingDetectionTimer: Timer?
    /// How many consecutive seconds of audio detected during meeting detection.
    private var meetingAudioDetectedSeconds: Int = 0
    /// Total seconds elapsed in meeting detection mode.
    private var meetingDetectionElapsed: Int = 0
    /// Set of calendar event identifiers already triggered, to avoid re-triggering.
    private var triggeredCalendarEventIds: Set<String> = []
    /// Grace period: don't check silence for the first N seconds of an auto-recording.
    private static let silenceGracePeriodSeconds = 15
    /// Rolling window size in seconds — auto-stop if mostly silent over this period.
    private static let silenceWindowSize = 45
    /// Fraction of samples in the window that must be silent to trigger auto-stop.
    private static let silenceWindowThreshold = 0.85
    /// Audio level below this is considered silence (0..1 scale).
    private static let silenceLevelThreshold: Float = 0.005
    /// Grace period after calendar event end before auto-stopping (seconds).
    private static let calendarEndGracePeriodSeconds: TimeInterval = 15 * 60
    /// How many consecutive seconds of audio needed to confirm a meeting has started.
    private static let meetingAudioConfirmSeconds = 5
    /// How long to wait for meeting audio before giving up (seconds).
    private static let meetingDetectionTimeoutSeconds = 600  // 10 minutes
    /// Audio level above this is considered meeting audio (0..1 scale).
    private static let meetingAudioThreshold: Float = 0.01

    init() {
        let mm = ModelManager()
        modelManager = mm
        mlxModelManager = MLXModelManager()
        transcriptionService = TranscriptionService(modelManager: mm)
        meetingStore = MeetingStore()

        // Restore Ollama server URL (default to localhost)
        let savedURL = UserDefaults.standard.string(forKey: "ollamaServerURL") ?? OllamaClient.defaultBaseURL
        ollamaServerURL = savedURL
        summarizationService = SummarizationService(ollamaBaseURL: savedURL)

        // Restore persisted settings
        summarizationBackend = UserDefaults.standard.string(forKey: "summarizationBackend") ?? "mlx"
        selectedMLXModel = UserDefaults.standard.string(forKey: "selectedMLXModel")
        selectedOllamaModel = UserDefaults.standard.string(forKey: "selectedOllamaModel")
        micEnabled = UserDefaults.standard.object(forKey: "micEnabled") as? Bool ?? true
        let savedMicGain = UserDefaults.standard.float(forKey: "micGain")
        micGain = savedMicGain > 0 ? savedMicGain : 2.0
        autoRecordEnabled = UserDefaults.standard.bool(forKey: "autoRecordEnabled")
        calendarAutoRecordEnabled = UserDefaults.standard.bool(forKey: "calendarAutoRecordEnabled")
        googleAuthService.loadCachedAuthState()
        googleCalendarEmail = googleAuthService.signedInEmail
        let savedRetention = UserDefaults.standard.integer(forKey: "recordingRetentionDays")
        recordingRetentionDays = savedRetention > 0 ? savedRetention : 28
        speechRecognitionOnDeviceOnly = UserDefaults.standard.object(forKey: "speechRecognitionOnDeviceOnly") as? Bool ?? true
        customSystemPrompt = UserDefaults.standard.string(forKey: "customSystemPrompt")

        // Show onboarding if never completed
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showingOnboarding = true
        }

        // Ensure a valid WhisperKit model is always selected
        let knownIds = mm.models.map(\.id)
        if mm.selectedModelName == nil || !knownIds.contains(mm.selectedModelName!) {
            mm.selectModel("large-v3")
        }

        // Clean up recordings older than the retention period
        captureService.cleanupOldRecordings(retentionDays: recordingRetentionDays)
    }

    func startRecording() {
        Task {
            do {
                // Set up SFSpeech live transcriber — request authorization lazily on first use
                let transcriber: SpeechStreamingTranscriber?
                var speechStatus = SpeechStreamingTranscriber.authorizationStatus
                if speechStatus == .notDetermined {
                    speechStatus = await SpeechStreamingTranscriber.requestAuthorization()
                }
                if speechStatus == .authorized {
                    let t = SpeechStreamingTranscriber(onDeviceOnly: speechRecognitionOnDeviceOnly)
                    self.speechTranscriber = t
                    transcriber = t
                } else {
                    logger.info("SFSpeech not authorized (\(speechStatus.rawValue)) — recording without live text")
                    transcriber = nil
                }

                // Wire audio buffer forwarding to SFSpeech
                if let transcriber {
                    captureService.onAudioBuffer = { [weak transcriber] buffer in
                        transcriber?.appendBuffer(buffer)
                    }
                }

                try await captureService.startCapture(
                    micEnabled: micEnabled,
                    micDeviceUID: micEnabled ? audioDeviceManager.selectedInputDeviceUID : nil,
                    micGain: micGain
                )
                let now = Date()
                phase = .recording(since: now, liveText: "")

                // Reset live transcript buffer
                liveTranscriptSegments = []
                currentChunkText = ""
                lastCallbackTextLength = 0
                currentChunkStartDate = now
                liveTextRecordingStart = now

                // Create DB record
                let appName = detectMeetingApp()
                if let audio = buildCurrentAudio(startedAt: now) {
                    let record = try meetingStore.createMeeting(
                        startedAt: now,
                        appName: appName,
                        audio: audio
                    )
                    currentMeetingId = record.id

                    // Query calendar for meeting participants (EventKit first, Google Calendar fallback)
                    if let calendarMeeting = await calendarService.findCurrentMeetingWithFallback(
                        around: now,
                        appName: appName,
                        googleAuthService: googleAuthService
                    ) {
                        currentMeetingParticipants = calendarMeeting.participants
                        currentMeetingCalendarEndTime = calendarMeeting.end
                        try? meetingStore.updateWithCalendarInfo(
                            id: record.id,
                            calendarTitle: calendarMeeting.title,
                            participants: calendarMeeting.participants,
                            eventId: calendarMeeting.eventIdentifier,
                            eventEnd: calendarMeeting.end
                        )

                        // If auto-triggered and no end timer yet, arm one from calendar end time
                        if autoRecordTrigger != nil, calendarEndTimer == nil {
                            armCalendarEndTimer(endTime: calendarMeeting.end)
                        }
                    }
                }

                // Wire live text updates and start SFSpeech
                if let transcriber {
                    transcriber.onTextUpdated = { [weak self] text in
                        guard let self else { return }
                        self.bufferLiveText(text)
                    }
                    transcriber.start()
                }
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "AppState")

    func stopRecording() {
        // Clear auto-record trigger so app termination won't try to stop again
        stopSilenceMonitoring()
        autoRecordTrigger = nil

        // Commit whatever's in the current chunk before we destroy anything
        commitCurrentChunk()

        // Stop SFSpeech live transcriber
        speechTranscriber?.stop()
        speechTranscriber = nil
        captureService.onAudioBuffer = nil

        if let result = captureService.stopCapture() {
            phase = .stopped(result)

            // Update DB with duration
            if let id = currentMeetingId {
                try? meetingStore.updateWithRecordingComplete(id: id, duration: result.duration)
            }

            // Use live transcript buffer if we have segments, otherwise WhisperKit fallback
            if !liveTranscriptSegments.isEmpty {
                // Fix up the last segment's endTime to match actual duration
                let lastIdx = liveTranscriptSegments.count - 1
                liveTranscriptSegments[lastIdx] = TranscriptSegment(
                    text: liveTranscriptSegments[lastIdx].text,
                    startTime: liveTranscriptSegments[lastIdx].startTime,
                    endTime: result.duration
                )

                let fullText = liveTranscriptSegments.map(\.text).joined(separator: " ")
                let transcript = TimestampedTranscript(segments: liveTranscriptSegments, fullText: fullText)
                logger.info("Using live transcript buffer: \(self.liveTranscriptSegments.count) segments, \(fullText.count) chars — skipping WhisperKit")
                startTranscriptionWithStreamingSegments(audio: result, streamingTranscript: transcript)
            } else {
                logger.info("No live transcript — falling back to WhisperKit batch transcription")
                startTranscription(audio: result)
            }
        } else {
            phase = .idle
        }
    }

    func startTranscription(audio: CapturedAudio) {
        phase = .transcribing(audio, progress: 0)

        Task {
            // Observe progress from transcription service
            let progressTask = Task {
                for await _ in transcriptionService.$progress.values {
                    if case .transcribing(let a, _) = phase {
                        phase = .transcribing(a, progress: transcriptionService.progress)
                    }
                }
            }

            do {
                let result = try await transcriptionService.transcribe(audio: audio)
                progressTask.cancel()
                phase = .transcribed(audio, result)

                // Update DB with transcription
                if let id = currentMeetingId {
                    try? meetingStore.updateWithTranscription(id: id, transcription: result)
                }

                // Auto-start summarization if a model is selected and available
                autoStartSummarization(audio: audio, transcription: result)
            } catch {
                progressTask.cancel()
                phase = .error(error.localizedDescription)

                if let id = currentMeetingId {
                    try? meetingStore.updateStatus(id: id, status: "error")
                }
            }
        }
    }

    /// Use streaming transcript for system audio and only transcribe mic audio from file.
    func startTranscriptionWithStreamingSegments(audio: CapturedAudio, streamingTranscript: TimestampedTranscript) {
        phase = .transcribing(audio, progress: 0.5)

        Task {
            do {
                let result = try await transcriptionService.transcribeWithStreamingSegments(
                    audio: audio,
                    systemTranscript: streamingTranscript
                )
                phase = .transcribed(audio, result)

                if let id = currentMeetingId {
                    try? meetingStore.updateWithTranscription(id: id, transcription: result)
                }

                // Auto-start summarization
                autoStartSummarization(audio: audio, transcription: result)
            } catch {
                phase = .error(error.localizedDescription)
                if let id = currentMeetingId {
                    try? meetingStore.updateStatus(id: id, status: "error")
                }
            }
        }
    }

    /// Attempt to auto-start summarization after transcription completes.
    /// Logs the reason if summarization is skipped.
    private func autoStartSummarization(audio: CapturedAudio, transcription: MeetingTranscription) {
        logger.info("Auto-summarization check: backend=\(self.summarizationBackend), transcript=\(transcription.combinedText.count) chars")

        if summarizationBackend == "mlx" {
            guard let modelId = selectedMLXModel else {
                logger.info("Auto-summarization skipped: no MLX model selected")
                return
            }
            guard mlxModelManager.modelIsDownloaded(modelId) else {
                logger.info("Auto-summarization skipped: MLX model '\(modelId)' not downloaded")
                return
            }
            startSummarization(audio: audio, transcription: transcription)
        } else {
            guard selectedOllamaModel != nil else {
                logger.info("Auto-summarization skipped: no Ollama model selected")
                return
            }
            Task {
                let available = await summarizationService.ollamaClient.checkAvailability()
                guard available else {
                    logger.info("Auto-summarization skipped: Ollama not available")
                    return
                }
                startSummarization(audio: audio, transcription: transcription)
            }
        }
    }

    /// Check whether a transcript has enough meaningful content to warrant summarization.
    /// Returns true if the transcript has at least 50 words with sufficient variety.
    private func transcriptHasSufficientContent(_ transcription: MeetingTranscription) -> Bool {
        let text = transcription.combinedText
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { $0.lowercased() }

        // Need at least 50 words
        guard words.count >= 50 else {
            logger.info("Transcript too short for summarization: \(words.count) words (need 50)")
            return false
        }

        // Check unique word ratio to filter repetitive noise ("um um um um...")
        let uniqueWords = Set(words)
        let uniqueRatio = Double(uniqueWords.count) / Double(words.count)
        guard uniqueRatio > 0.15 else {
            logger.info("Transcript too repetitive for summarization: \(String(format: "%.0f", uniqueRatio * 100))% unique words (\(uniqueWords.count)/\(words.count))")
            return false
        }

        logger.info("Transcript content check passed: \(words.count) words, \(String(format: "%.0f", uniqueRatio * 100))% unique")
        return true
    }

    func startSummarization(audio: CapturedAudio, transcription: MeetingTranscription) {
        // Gate: skip summarization if transcript lacks meaningful content
        guard transcriptHasSufficientContent(transcription) else {
            logger.info("Skipping summarization — insufficient transcript content")
            return
        }

        // Pass custom system prompt to summarization service
        summarizationService.customSystemPrompt = customSystemPrompt

        if summarizationBackend == "mlx" {
            guard let modelId = selectedMLXModel else {
                phase = .error(SummarizationError.mlxModelNotSelected.localizedDescription)
                return
            }
            summarizationService.backend = .mlx
            summarizationService.selectedMLXModelId = modelId
        } else {
            guard let model = selectedOllamaModel else {
                phase = .error(SummarizationError.noModelSelected.localizedDescription)
                return
            }
            summarizationService.backend = .ollama
            summarizationService.selectedModel = model
        }

        phase = .summarizing(audio, transcription)

        Task {
            do {
                // Load participants from current state or DB
                let participants = currentMeetingParticipants ?? {
                    guard let id = currentMeetingId else { return nil }
                    return try? meetingStore.loadMeeting(id: id)?.decodedParticipants()
                }()

                let summary = try await summarizationService.summarize(
                    transcript: transcription.combinedText,
                    appName: nil,
                    duration: audio.duration,
                    participants: participants
                )
                phase = .summarized(audio, transcription, summary)

                // Update DB with summary
                if let id = currentMeetingId {
                    try? meetingStore.updateWithSummary(id: id, summary: summary)
                }
            } catch {
                phase = .error(error.localizedDescription)

                if let id = currentMeetingId {
                    try? meetingStore.updateStatus(id: id, status: "error")
                }
            }
        }
    }

    // MARK: - Auto-Record

    func handleMeetingAppLaunched(appName: String) {
        guard autoRecordEnabled, case .idle = phase else { return }
        logger.info("Auto-starting recording for \(appName, privacy: .public)")
        autoRecordTrigger = .meetingApp(appName)
        startRecording()
        startSilenceMonitoring()
    }

    func handleMeetingAppTerminated(appName: String) {
        guard case .meetingApp(let triggerApp) = autoRecordTrigger, triggerApp == appName else { return }
        // Only stop if we're still recording
        if case .recording = phase {
            logger.info("Auto-stopping recording — \(appName, privacy: .public) terminated")
            stopSilenceMonitoring()
            autoRecordTrigger = nil
            stopRecording()
        } else {
            stopSilenceMonitoring()
            autoRecordTrigger = nil
        }
    }

    // MARK: - Meeting Audio Detection

    /// Start lightweight audio monitoring to detect when a meeting actually begins.
    private func startMeetingDetection() {
        meetingAudioDetectedSeconds = 0

        Task {
            do {
                try await captureService.startMonitoring()
            } catch {
                logger.warning("Failed to start audio monitoring: \(error.localizedDescription, privacy: .public)")
                // Fall back to immediate recording
                startRecording()
                startSilenceMonitoring()
                return
            }

            // Check audio levels every second
            meetingDetectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.checkMeetingAudio()
                }
            }
        }
    }

    private func stopMeetingDetection() {
        meetingDetectionTimer?.invalidate()
        meetingDetectionTimer = nil
        meetingAudioDetectedSeconds = 0
        meetingDetectionElapsed = 0
        captureService.stopMonitoring()
    }

    private func checkMeetingAudio() {
        guard autoRecordTrigger != nil, captureService.isMonitoring else {
            stopMeetingDetection()
            return
        }

        meetingDetectionElapsed += 1

        // Timeout: give up after 10 minutes of no meeting
        if meetingDetectionElapsed >= Self.meetingDetectionTimeoutSeconds {
            logger.info("Meeting detection timed out after \(Self.meetingDetectionTimeoutSeconds)s — cancelling")
            stopMeetingDetection()
            autoRecordTrigger = nil
            return
        }

        let level = captureService.systemAudioLevel

        if level >= Self.meetingAudioThreshold {
            meetingAudioDetectedSeconds += 1
            logger.debug("Meeting audio detected: \(self.meetingAudioDetectedSeconds)/\(Self.meetingAudioConfirmSeconds)s (level: \(level))")

            if meetingAudioDetectedSeconds >= Self.meetingAudioConfirmSeconds {
                logger.info("Meeting confirmed — starting recording")
                stopMeetingDetection()
                startRecording()
                startSilenceMonitoring()
            }
        } else {
            if meetingAudioDetectedSeconds > 0 {
                logger.debug("Meeting audio lost, resetting (level: \(level))")
            }
            meetingAudioDetectedSeconds = 0
        }
    }

    func handleUpcomingCalendarMeeting(_ meeting: CalendarMeeting) {
        guard calendarAutoRecordEnabled, case .idle = phase else { return }
        // Dedup: don't re-trigger for the same event
        guard !triggeredCalendarEventIds.contains(meeting.eventIdentifier) else { return }
        triggeredCalendarEventIds.insert(meeting.eventIdentifier)

        logger.info("Auto-starting recording for calendar event: \(meeting.title, privacy: .public)")
        autoRecordTrigger = .calendarEvent(meeting.title)
        currentMeetingParticipants = meeting.participants
        currentMeetingCalendarEndTime = meeting.end
        startRecording()
        startSilenceMonitoring()
        armCalendarEndTimer(endTime: meeting.end)
    }

    /// Start a 1-second timer that monitors audio level during auto-recordings.
    /// After a grace period, if audio is mostly silent over a rolling window, auto-stops.
    private func startSilenceMonitoring() {
        silenceWindow = []
        silenceMonitorElapsed = -Self.silenceGracePeriodSeconds

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkSilence()
            }
        }
    }

    private func stopSilenceMonitoring() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        calendarEndTimer?.invalidate()
        calendarEndTimer = nil
        silenceWindow = []
        silenceMonitorElapsed = 0
    }

    /// Schedule a one-shot timer to auto-stop recording after the calendar event's end time + grace period.
    private func armCalendarEndTimer(endTime: Date) {
        calendarEndTimer?.invalidate()
        let fireDate = endTime.addingTimeInterval(Self.calendarEndGracePeriodSeconds)
        let interval = fireDate.timeIntervalSinceNow

        guard interval > 0 else {
            // Event already past end + grace — don't arm
            logger.info("Calendar event already past end+grace, not arming timer")
            return
        }

        logger.info("Arming calendar end timer for \(Int(interval))s from now")
        calendarEndTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleCalendarEndTimerFired()
            }
        }
    }

    private func handleCalendarEndTimerFired() {
        calendarEndTimer = nil
        guard autoRecordTrigger != nil, case .recording = phase else { return }
        logger.info("Auto-stopping recording — calendar event end time + grace period reached")
        stopSilenceMonitoring()
        autoRecordTrigger = nil
        stopRecording()
    }

    private func checkSilence() {
        // Only monitor during auto-started recordings
        guard autoRecordTrigger != nil, case .recording = phase else {
            stopSilenceMonitoring()
            return
        }

        silenceMonitorElapsed += 1

        // Grace period — don't evaluate yet
        if silenceMonitorElapsed <= 0 {
            logger.debug("Silence monitor grace period: \(-self.silenceMonitorElapsed)s remaining")
            return
        }

        let level = captureService.systemAudioLevel
        let isSilent = level < Self.silenceLevelThreshold

        // Add to rolling window, keep at most windowSize entries
        silenceWindow.append(isSilent)
        if silenceWindow.count > Self.silenceWindowSize {
            silenceWindow.removeFirst(silenceWindow.count - Self.silenceWindowSize)
        }

        // Need a full window before evaluating
        guard silenceWindow.count >= Self.silenceWindowSize else {
            let silentCount = silenceWindow.filter { $0 }.count
            logger.debug("Silence window filling: \(silentCount)/\(self.silenceWindow.count) silent (level: \(level))")
            return
        }

        let silentCount = silenceWindow.filter { $0 }.count
        let silentFraction = Double(silentCount) / Double(Self.silenceWindowSize)

        if silentFraction >= Self.silenceWindowThreshold {
            logger.info("Auto-stopping recording — \(Int(silentFraction * 100))% silent over \(Self.silenceWindowSize)s window")
            stopSilenceMonitoring()
            autoRecordTrigger = nil
            stopRecording()
        } else if isSilent {
            logger.debug("Silence window: \(silentCount)/\(Self.silenceWindowSize) silent (\(Int(silentFraction * 100))%, need \(Int(Self.silenceWindowThreshold * 100))%)")
        }
    }

    func reset() {
        phase = .idle
        showingModelPicker = false
        currentMeetingId = nil
        currentMeetingParticipants = nil
        currentMeetingCalendarEndTime = nil
        liveTranscriptSegments = []
        currentChunkText = ""
        lastCallbackTextLength = 0
        autoRecordTrigger = nil
        stopMeetingDetection()
        meetingStore.loadRecentMeetings()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        showingOnboarding = false
    }

    // MARK: - Helpers

    /// Detect if a known meeting/conferencing app is currently running.
    private func detectMeetingApp() -> String? {
        let meetingApps: [(bundlePrefix: String, displayName: String)] = [
            ("us.zoom.xos", "Zoom"),
            ("com.microsoft.teams", "Microsoft Teams"),
            ("com.cisco.webexmeetingsapp", "Webex"),
            ("com.google.Chrome", "Google Meet"),       // Meet runs in Chrome
            ("com.apple.Safari", "Safari"),              // Meet/other web conferencing
            ("com.brave.Browser", "Brave"),
            ("org.mozilla.firefox", "Firefox"),
            ("com.microsoft.edgemac", "Microsoft Edge"),
            ("com.slack.Slack", "Slack"),
            ("com.apple.FaceTime", "FaceTime"),
            ("com.discord.Discord", "Discord"),
        ]

        let runningBundles = NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleIdentifier }

        for app in meetingApps {
            if runningBundles.contains(where: { $0.hasPrefix(app.bundlePrefix) }) {
                return app.displayName
            }
        }

        return nil
    }

    // MARK: - Live Transcript Buffer

    /// Called on every SFSpeech text update. Detects when text shrinks (session reset)
    /// and commits the previous chunk as a timestamped segment. Only appends, never deletes.
    private func bufferLiveText(_ text: String) {
        let now = Date.now

        // Text shrank → SFSpeech reset internally or session restarted.
        // Commit what we had as a finished segment.
        if text.count < lastCallbackTextLength {
            commitCurrentChunk()
            currentChunkStartDate = now
        }

        // Always store the latest text for the current chunk
        currentChunkText = text
        lastCallbackTextLength = text.count

        // Build the full display text from all committed segments + current chunk
        let displayText = buildFullText()
        if case .recording(let since, _) = self.phase {
            self.phase = .recording(since: since, liveText: displayText)
        }
    }

    /// Commit currentChunkText as a timestamped segment. No-op if empty.
    private func commitCurrentChunk() {
        let trimmed = currentChunkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let startTime = currentChunkStartDate.timeIntervalSince(liveTextRecordingStart)
        let endTime = Date.now.timeIntervalSince(liveTextRecordingStart)

        liveTranscriptSegments.append(TranscriptSegment(
            text: trimmed,
            startTime: max(0, startTime),
            endTime: max(startTime + 0.1, endTime)
        ))

        logger.info("Committed transcript chunk: \(trimmed.count) chars at \(String(format: "%.1f", startTime))s (total segments: \(self.liveTranscriptSegments.count))")

        currentChunkText = ""
        lastCallbackTextLength = 0
    }

    /// Full text from all committed segments + current chunk.
    private func buildFullText() -> String {
        var parts = liveTranscriptSegments.map(\.text)
        let current = currentChunkText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            parts.append(current)
        }
        return parts.joined(separator: " ")
    }

    /// Build a minimal CapturedAudio for the DB record at recording start.
    /// The actual audio files are being written to; we just need the directory info.
    private func buildCurrentAudio(startedAt: Date) -> CapturedAudio? {
        // The capture service has already created the output directory at this point.
        // We need to read it from the service's internal state.
        // Since the service doesn't expose the directory, we reconstruct it.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordings = appSupport
            .appendingPathComponent("NoteTaker", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)

        // Find the most recently created directory
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: recordings, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return nil
        }

        let sorted = contents.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return dateA > dateB
        }

        guard let latestDir = sorted.first else { return nil }

        return CapturedAudio(
            systemAudioURL: latestDir.appendingPathComponent("system.m4a"),
            microphoneURL: nil,
            directory: latestDir,
            startedAt: startedAt,
            duration: 0
        )
    }
}
