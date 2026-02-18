import SwiftUI
import Combine
import AppKit

/// Centralized app state tying together process discovery, audio capture, and UI phase.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case stopped(CapturedAudio)
        case transcribing(CapturedAudio, progress: Double)
        case transcribed(CapturedAudio, MeetingTranscription)
        case summarizing(CapturedAudio, MeetingTranscription)
        case summarized(CapturedAudio, MeetingTranscription, MeetingSummary)
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): true
            case (.recording(let a), .recording(let b)): a == b
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

    @Published var ollamaServerURL: String {
        didSet {
            UserDefaults.standard.set(ollamaServerURL, forKey: "ollamaServerURL")
            summarizationService.updateBaseURL(ollamaServerURL)
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

    private var currentMeetingId: String?

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

        // Show onboarding if never completed
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            showingOnboarding = true
        }

        // Ensure a valid WhisperKit model is always selected
        let knownIds = mm.models.map(\.id)
        if mm.selectedModelName == nil || !knownIds.contains(mm.selectedModelName!) {
            mm.selectModel("large-v3")
        }
    }

    func startRecording() {
        do {
            try captureService.startCapture(inputDeviceID: audioDeviceManager.selectedDeviceID)
            let now = Date()
            phase = .recording(since: now)

            // Create DB record
            if let audio = buildCurrentAudio(startedAt: now) {
                let record = try meetingStore.createMeeting(
                    startedAt: now,
                    appName: detectMeetingApp(),
                    audio: audio
                )
                currentMeetingId = record.id
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func stopRecording() {
        if let result = captureService.stopCapture() {
            phase = .stopped(result)

            // Update DB with duration
            if let id = currentMeetingId {
                try? meetingStore.updateWithRecordingComplete(id: id, duration: result.duration)
            }

            // Auto-start transcription
            startTranscription(audio: result)
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
                if summarizationBackend == "mlx" {
                    if let modelId = selectedMLXModel, mlxModelManager.modelIsDownloaded(modelId) {
                        startSummarization(audio: audio, transcription: result)
                    }
                } else {
                    if selectedOllamaModel != nil {
                        let available = await summarizationService.ollamaClient.checkAvailability()
                        if available {
                            startSummarization(audio: audio, transcription: result)
                        }
                    }
                }
            } catch {
                progressTask.cancel()
                phase = .error(error.localizedDescription)

                if let id = currentMeetingId {
                    try? meetingStore.updateStatus(id: id, status: "error")
                }
            }
        }
    }

    func startSummarization(audio: CapturedAudio, transcription: MeetingTranscription) {
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
                let summary = try await summarizationService.summarize(
                    transcript: transcription.combinedText,
                    appName: nil,
                    duration: audio.duration
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

    func reset() {
        phase = .idle
        showingModelPicker = false
        currentMeetingId = nil
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
            systemAudioURL: latestDir.appendingPathComponent("system.wav"),
            microphoneURL: latestDir.appendingPathComponent("mic.wav"),
            directory: latestDir,
            startedAt: startedAt,
            duration: 0
        )
    }
}
