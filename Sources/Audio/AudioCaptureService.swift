import Foundation
import AVFoundation
import OSLog

/// Coordinates system audio capture (via Core Audio Taps) and microphone capture.
/// Manages output directory creation and publishes audio levels for the UI.
@MainActor
final class AudioCaptureService: ObservableObject {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "AudioCaptureService")

    @Published private(set) var systemAudioLevel: Float = 0
    @Published private(set) var micAudioLevel: Float = 0
    @Published private(set) var isRecording = false

    private var systemTap: SystemAudioTap?
    private var systemRecorder: SystemAudioRecorder?
    private var micCapture: MicrophoneCapture?

    private var recordingStartTime: Date?
    private var outputDirectory: URL?

    // Pre-warm mic capture at init
    init() {
        micCapture = MicrophoneCapture()
    }

    // MARK: - Public API

    func startCapture() throws {
        guard !isRecording else { return }

        logger.info("Starting global audio capture")

        // Create output directory
        let dir = try createOutputDirectory()
        self.outputDirectory = dir

        let systemURL = dir.appendingPathComponent("system.wav")
        let micURL = dir.appendingPathComponent("mic.wav")

        // 1. Create and activate system audio tap
        let tap = SystemAudioTap()
        try tap.activate()
        self.systemTap = tap

        // 2. Start system audio recorder
        let recorder = SystemAudioRecorder(fileURL: systemURL, tap: tap)
        recorder.onLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.systemAudioLevel = level
            }
        }
        try recorder.start()
        self.systemRecorder = recorder

        // 3. Start microphone capture with tap's format for synchronization
        if micCapture == nil {
            micCapture = MicrophoneCapture()
        }
        let mic = micCapture!
        mic.onLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.micAudioLevel = level
            }
        }
        try mic.start(outputURL: micURL, tapStreamDescription: recorder.tapStreamDescription)

        recordingStartTime = Date()
        isRecording = true

        logger.info("Capture started. Output: \(dir.path, privacy: .public)")
    }

    func stopCapture() -> CapturedAudio? {
        guard isRecording else { return nil }

        logger.info("Stopping capture")

        let startTime = recordingStartTime ?? Date()
        let duration = Date().timeIntervalSince(startTime)

        // Stop mic first (less critical), then system recorder
        micCapture?.stop()
        systemRecorder?.stop()

        // Reset levels
        systemAudioLevel = 0
        micAudioLevel = 0
        isRecording = false

        guard let dir = outputDirectory else { return nil }

        let result = CapturedAudio(
            systemAudioURL: dir.appendingPathComponent("system.wav"),
            microphoneURL: dir.appendingPathComponent("mic.wav"),
            directory: dir,
            startedAt: startTime,
            duration: duration
        )

        // Clean up references
        systemRecorder = nil
        systemTap = nil
        outputDirectory = nil
        recordingStartTime = nil

        logger.info("Capture stopped. Duration: \(result.formattedDuration)")

        return result
    }

    // MARK: - Output Directory

    private func createOutputDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordings = appSupport
            .appendingPathComponent("NoteTaker", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let dir = recordings.appendingPathComponent(timestamp, isDirectory: true)

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        return dir
    }
}
