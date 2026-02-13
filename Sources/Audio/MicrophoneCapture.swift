import AVFoundation
import OSLog

/// Captures microphone audio using AVAudioEngine, writing to a WAV file.
/// Accepts an optional target format from SystemAudioTap for format synchronization.
final class MicrophoneCapture {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "MicrophoneCapture")

    private var audioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?

    private var inputFormat: AVAudioFormat?
    private var targetFormat: AVAudioFormat?

    private var preparationTask: Task<Void, Never>?
    private var isPreWarmed = false

    private(set) var isRecording = false

    /// Current audio level. Updated from tap callback.
    var onLevelUpdate: ((Float) -> Void)?

    init() {
        preWarm()
    }

    deinit {
        preparationTask?.cancel()
        cleanup()
    }

    // MARK: - Pre-warming

    /// Pre-warm AVAudioEngine in background to avoid 50-100ms latency on first use.
    private func preWarm() {
        preparationTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try self.prepareEngine()
                await MainActor.run { self.isPreWarmed = true }
                self.logger.info("AVAudioEngine pre-warmed")
            } catch {
                self.logger.error("Pre-warm failed: \(error, privacy: .public)")
            }
        }
    }

    private func prepareEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(inputNode, to: mixer, format: format)

        self.audioEngine = engine
        self.mixerNode = mixer
        self.inputFormat = format

        logger.info("Engine prepared: \(format.sampleRate)Hz, \(format.channelCount)ch")
    }

    private func waitForPreWarm() {
        let deadline = CFAbsoluteTimeGetCurrent() + 0.15
        while !isPreWarmed && CFAbsoluteTimeGetCurrent() < deadline {
            usleep(1000)
        }
    }

    // MARK: - Recording

    /// Start capturing microphone audio to `outputURL`.
    /// If `tapStreamDescription` is provided, the output file will match that format.
    func start(outputURL: URL, tapStreamDescription: AudioStreamBasicDescription? = nil) throws {
        guard !isRecording else { return }

        waitForPreWarm()

        // If engine wasn't pre-warmed, prepare now
        if audioEngine == nil {
            try prepareEngine()
        }

        guard let engine = audioEngine, let mixer = mixerNode, let inputFmt = inputFormat else {
            throw AudioCaptureError.coreAudioError("Audio engine not prepared")
        }

        // Determine output format
        if var desc = tapStreamDescription {
            targetFormat = AVAudioFormat(streamDescription: &desc)
            logger.info("Target format from tap: \(desc.mSampleRate)Hz, \(desc.mChannelsPerFrame)ch")
        }

        let outputFmt = targetFormat ?? inputFmt

        // Create output file
        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFmt.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: outputFmt.isInterleaved
        )
        self.audioFile = file

        // Set up converter if formats differ
        if needsConversion(from: inputFmt, to: outputFmt) {
            guard let conv = AVAudioConverter(from: inputFmt, to: outputFmt) else {
                throw AudioCaptureError.coreAudioError("Failed to create audio converter \(inputFmt) → \(outputFmt)")
            }
            self.converter = conv
            logger.info("Format conversion enabled: \(inputFmt.sampleRate)Hz→\(outputFmt.sampleRate)Hz")
        }

        // Install tap on mixer
        mixer.installTap(onBus: 0, bufferSize: 1024, format: inputFmt) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        try engine.start()
        isRecording = true

        logger.info("Microphone recording started → \(outputURL.lastPathComponent)")
    }

    func stop() {
        guard isRecording else { return }

        logger.debug("Stopping microphone recording")

        mixerNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        audioFile = nil
        converter = nil
        isRecording = false
    }

    // MARK: - Buffer Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile else { return }

        do {
            if let converter, let targetFmt = targetFormat {
                // Convert format before writing
                let convertedBuffer = try convert(buffer: buffer, using: converter, outputFormat: targetFmt)
                try file.write(from: convertedBuffer)
                onLevelUpdate?(AudioLevelMonitor.peakLevel(from: convertedBuffer))
            } else {
                try file.write(from: buffer)
                onLevelUpdate?(AudioLevelMonitor.peakLevel(from: buffer))
            }
        } catch {
            logger.error("Buffer write error: \(error, privacy: .public)")
        }
    }

    private func convert(
        buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else {
            throw AudioCaptureError.coreAudioError("Failed to allocate conversion buffer")
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            throw AudioCaptureError.coreAudioError("Conversion error: \(error.localizedDescription)")
        }

        return outputBuffer
    }

    private func needsConversion(from: AVAudioFormat, to: AVAudioFormat) -> Bool {
        from.sampleRate != to.sampleRate || from.channelCount != to.channelCount
    }

    private func cleanup() {
        if isRecording { stop() }
        if let engine = audioEngine {
            engine.stop()
            mixerNode?.removeTap(onBus: 0)
        }
        audioFile = nil
    }
}
