import Foundation
import AVFoundation
import OSLog

/// Coordinates system audio capture via ScreenCaptureKit.
/// Manages output directory creation and publishes audio levels for the UI.
@MainActor
final class AudioCaptureService: ObservableObject {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "AudioCaptureService")

    @Published private(set) var systemAudioLevel: Float = 0
    @Published private(set) var isRecording = false

    /// Raw audio buffer callback for streaming transcription. Called on audio queue.
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var systemRecorder: ScreenCaptureAudioRecorder?

    private var recordingStartTime: Date?
    private var outputDirectory: URL?

    // MARK: - Public API

    func startCapture(micEnabled: Bool = true, micDeviceUID: String? = nil) async throws {
        guard !isRecording else { return }

        logger.info("Starting audio capture")

        // Create output directory
        let dir = try createOutputDirectory()
        self.outputDirectory = dir

        let systemURL = dir.appendingPathComponent("system.m4a")

        // Start system audio recorder (ScreenCaptureKit) — captures all audio
        // including the local user's voice via meeting app mix
        let recorder = ScreenCaptureAudioRecorder(fileURL: systemURL)
        recorder.onLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.systemAudioLevel = level
            }
        }
        recorder.onAudioBuffer = { [weak self] buffer in
            self?.onAudioBuffer?(buffer)
        }
        try await recorder.start(micEnabled: micEnabled, micDeviceUID: micDeviceUID)
        self.systemRecorder = recorder

        recordingStartTime = Date()
        isRecording = true

        logger.info("Capture started. Output: \(dir.path, privacy: .public)")
    }

    func stopCapture() -> CapturedAudio? {
        guard isRecording else { return nil }

        logger.info("Stopping capture")

        let startTime = recordingStartTime ?? Date()
        let duration = Date().timeIntervalSince(startTime)

        systemRecorder?.stop()

        // Reset levels
        systemAudioLevel = 0
        isRecording = false

        guard let dir = outputDirectory else { return nil }

        let result = CapturedAudio(
            systemAudioURL: dir.appendingPathComponent("system.m4a"),
            microphoneURL: nil,
            directory: dir,
            startedAt: startTime,
            duration: duration
        )

        // Clean up references
        systemRecorder = nil
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

    // MARK: - Cleanup

    /// Removes recording directories older than the specified number of days.
    func cleanupOldRecordings(retentionDays: Int) {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupport
            .appendingPathComponent("NoteTaker", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)

        guard let contents = try? fm.contentsOfDirectory(
            at: recordingsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()

        for item in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let creationDate = (try? item.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            guard creationDate < cutoff else { continue }

            do {
                try fm.removeItem(at: item)
                logger.info("Removed expired recording: \(item.lastPathComponent, privacy: .public)")
            } catch {
                logger.warning("Failed to remove recording \(item.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}
