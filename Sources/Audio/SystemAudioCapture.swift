import AudioToolbox
import AVFoundation
import OSLog
import ScreenCaptureKit

// MARK: - ScreenCaptureAudioRecorder

/// Captures system audio using ScreenCaptureKit's SCStream (audio-only mode).
/// Replaces the previous Core Audio Taps approach which delivered silent buffers
/// in many configurations (Bluetooth output, permission edge cases, etc.).
final class ScreenCaptureAudioRecorder: NSObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "ScreenCaptureAudioRecorder")
    private let queue = DispatchQueue(label: "com.incept5.NoteTaker.SCStreamAudio", qos: .userInitiated)

    let fileURL: URL
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?

    private(set) var isRecording = false

    /// Audio stream description for synchronizing mic capture format.
    /// Set to 48kHz stereo float32 — the default ScreenCaptureKit audio format.
    private(set) var tapStreamDescription: AudioStreamBasicDescription?

    /// Current audio level, updated from the stream callback. Read from main actor for UI.
    var onLevelUpdate: ((Float) -> Void)?

    /// Raw audio buffer callback for streaming transcription. Called on the audio queue.
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init()

        // Pre-populate with the known ScreenCaptureKit default format (48kHz stereo float32)
        var desc = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        self.tapStreamDescription = desc

        // Create the output file immediately with the known format
        if let format = AVAudioFormat(streamDescription: &desc) {
            self.audioFormat = format
            do {
                self.audioFile = try AVAudioFile(
                    forWriting: fileURL,
                    settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: format.sampleRate,
                        AVNumberOfChannelsKey: format.channelCount,
                        AVLinearPCMBitDepthKey: 32,
                        AVLinearPCMIsFloatKey: true,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: true,
                    ],
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
            } catch {
                logger.error("Failed to create audio file: \(error, privacy: .public)")
            }
        }
    }

    /// Start capturing system audio. Requires Screen Recording permission.
    func start() async throws {
        guard !isRecording else { return }

        logger.info("Starting ScreenCaptureKit audio capture")

        // Get shareable content (requires Screen Recording permission).
        // On macOS 15+, granting permission requires an app restart to take effect.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            logger.error("SCShareableContent failed: \(error, privacy: .public)")
            throw AudioCaptureError.screenCaptureNotAvailable(
                "Screen Recording permission required. Grant access in System Settings > Privacy & Security > Screen Recording, then fully quit and relaunch NoteTaker."
            )
        }

        guard let display = content.displays.first else {
            throw AudioCaptureError.screenCaptureNotAvailable("No displays found")
        }

        // Configure for audio-only capture
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        // Explicitly disable microphone capture (macOS 15+) — we handle mic separately
        if #available(macOS 15.0, *) {
            config.captureMicrophone = false
        }

        // Minimize video overhead — we only want audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum
        config.showsCursor = false

        // Create a filter that captures all audio from the display
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)

        do {
            try await scStream.startCapture()
        } catch {
            throw AudioCaptureError.streamStartFailed(
                "Failed to start audio capture: \(error.localizedDescription)"
            )
        }

        self.stream = scStream
        isRecording = true

        logger.info("System audio capture started → \(self.fileURL.lastPathComponent)")
    }

    func stop() {
        guard isRecording else { return }

        logger.debug("Stopping system audio capture")

        isRecording = false

        if let stream {
            // Stop capture asynchronously — fire and forget since we're tearing down
            let capturedStream = stream
            self.stream = nil
            Task {
                do {
                    try await capturedStream.stopCapture()
                } catch {
                    // Already tearing down, log but don't throw
                    Logger(subsystem: "com.incept5.NoteTaker", category: "ScreenCaptureAudioRecorder")
                        .warning("stopCapture error (non-fatal): \(error, privacy: .public)")
                }
            }
        }

        audioFile = nil
    }

    deinit {
        stop()
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureAudioRecorder: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else { return }
        guard isRecording else { return }

        // Extract audio buffer list from the sample buffer
        var blockBuffer: CMBlockBuffer?
        var bufferListSizeNeeded: Int = 0

        // First call: determine the size needed
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard sizeStatus == noErr || sizeStatus == kCMSampleBufferError_ArrayTooSmall else {
            return
        }

        // Allocate buffer list and extract audio data
        let audioBufferList = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(audioBufferList.unsafeMutablePointer) }

        blockBuffer = nil
        let extractStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList.unsafeMutablePointer,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )

        guard extractStatus == noErr else { return }

        // Get or create format from the sample buffer
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }

        // Update format on first buffer if it differs from our default
        let format: AVAudioFormat
        if let existingFormat = audioFormat {
            format = existingFormat
        } else {
            var desc = asbd.pointee
            guard let newFormat = AVAudioFormat(streamDescription: &desc) else { return }
            audioFormat = newFormat
            tapStreamDescription = desc
            format = newFormat
        }

        // Create PCM buffer from the extracted audio data
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            bufferListNoCopy: audioBufferList.unsafePointer,
            deallocator: nil
        ) else {
            return
        }

        // Write to file
        guard let file = audioFile else { return }
        do {
            try file.write(from: buffer)
        } catch {
            Logger(subsystem: "com.incept5.NoteTaker", category: "ScreenCaptureAudioRecorder")
                .error("Write error: \(error, privacy: .public)")
        }

        // Forward buffer for streaming transcription
        onAudioBuffer?(buffer)

        // Update audio level
        let level = AudioLevelMonitor.peakLevel(from: buffer)
        onLevelUpdate?(level)
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureAudioRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Logger(subsystem: "com.incept5.NoteTaker", category: "ScreenCaptureAudioRecorder")
            .error("Stream stopped with error: \(error, privacy: .public)")
    }
}
