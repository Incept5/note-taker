import AVFoundation
import OSLog
import Speech

/// Thread-safe wrapper for an optional `SFSpeechAudioBufferRecognitionRequest`.
/// Allows the nonisolated `appendBuffer` to safely access the current request
/// while the @MainActor methods create/replace it during session restarts.
private final class AtomicReference<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T?

    func get() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

/// Wraps `SFSpeechRecognizer` for near-instant live transcription during recording.
///
/// Session restart logic handles Apple's ~60-second recognition limit (error 209)
/// by accumulating confirmed text in `textBuffer` and seamlessly starting a new
/// recognition session.
@MainActor
final class SpeechStreamingTranscriber {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "SpeechStreamingTranscriber")

    /// Called on the main actor when the full accumulated text updates.
    var onTextUpdated: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let requestRef = AtomicReference<SFSpeechAudioBufferRecognitionRequest>()
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Monotonically increasing session counter — ignores stale callbacks from old sessions.
    private var sessionID: Int = 0

    /// All confirmed text from previous sessions.
    private var textBuffer: String = ""

    /// Latest partial/final text from the current session.
    private var sessionLatest: String = ""

    /// Whether we're actively running.
    private var isRunning = false

    /// Throttle UI updates to avoid overwhelming SwiftUI.
    private var lastUpdateTime: Date = .distantPast
    private let updateThrottleInterval: TimeInterval = 0.05

    private let onDeviceOnly: Bool

    init(onDeviceOnly: Bool = true) {
        self.onDeviceOnly = onDeviceOnly
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Authorization

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    // MARK: - Start / Stop

    func start() {
        guard let recognizer, recognizer.isAvailable else {
            logger.warning("SFSpeechRecognizer not available")
            return
        }
        isRunning = true
        startSession()
    }

    func stop() {
        isRunning = false
        recognitionTask?.cancel()
        recognitionTask = nil
        requestRef.set(nil)
    }

    // MARK: - Audio Buffer Input

    /// Called from the audio capture queue with 48kHz stereo float32 buffers.
    /// `SFSpeechAudioBufferRecognitionRequest.append()` is thread-safe per Apple docs.
    nonisolated func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        requestRef.get()?.append(buffer)
    }

    // MARK: - Session Management

    private func startSession() {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if onDeviceOnly {
            request.requiresOnDeviceRecognition = true
        }
        // Add punctuation if available (macOS 15+)
        if #available(macOS 15, *) {
            request.addsPunctuation = true
        }

        requestRef.set(request)

        sessionID += 1
        let currentSession = sessionID

        logger.info("Starting speech recognition session \(currentSession)")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handleResult(result, error: error, session: currentSession)
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?, session: Int) {
        // Ignore callbacks from stale sessions
        guard session == sessionID else { return }

        if let result {
            let text = result.bestTranscription.formattedString

            // Detect within-session text shrink — SFSpeech sometimes internally resets
            // without firing error 209 or isFinal. If text drops significantly, commit
            // what we had before it's overwritten.
            if !sessionLatest.isEmpty && text.count < sessionLatest.count / 2 {
                logger.info("Within-session text shrink detected: \(self.sessionLatest.count) → \(text.count) chars — committing before overwrite")
                commitSession()
            }

            sessionLatest = text

            if result.isFinal {
                // Commit this session's text to the buffer
                commitSession()
                // Restart for continued recognition
                if isRunning {
                    startSession()
                }
            } else {
                throttledUpdate()
            }
        }

        if let error = error as? NSError {
            // Error 209 = recognition session timeout (~60s). Expected — just restart.
            // Error 216 = request was cancelled. Expected during stop/restart.
            if error.code == 209 {
                logger.info("Speech session \(session) timed out (error 209) — restarting")
                commitSession()
                if isRunning {
                    startSession()
                }
            } else if error.code == 216 {
                // Cancelled — no action needed
            } else {
                logger.warning("Speech recognition error: \(error.localizedDescription, privacy: .public)")
                // Try to restart on other errors
                commitSession()
                if isRunning {
                    // Brief delay before restart to avoid tight error loops
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        if self.isRunning {
                            self.startSession()
                        }
                    }
                }
            }
        }
    }

    private func commitSession() {
        guard !sessionLatest.isEmpty else { return }
        if textBuffer.isEmpty {
            textBuffer = sessionLatest
        } else {
            textBuffer += " " + sessionLatest
        }
        sessionLatest = ""
        emitUpdate()
    }

    // MARK: - UI Updates

    private func throttledUpdate() {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateThrottleInterval else { return }
        lastUpdateTime = now
        emitUpdate()
    }

    private func emitUpdate() {
        let fullText: String
        if textBuffer.isEmpty {
            fullText = sessionLatest
        } else if sessionLatest.isEmpty {
            fullText = textBuffer
        } else {
            fullText = textBuffer + " " + sessionLatest
        }
        onTextUpdated?(fullText)
    }
}
