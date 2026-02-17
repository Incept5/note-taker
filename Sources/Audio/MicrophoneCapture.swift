import AVFoundation
import AudioToolbox
import OSLog

/// Captures microphone audio using AVAudioEngine, writing to a WAV file.
/// Accepts an optional target format from SystemAudioTap for format synchronization.
/// Supports selecting a specific input device by AudioDeviceID.
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
    private var preparedDeviceID: AudioDeviceID?

    private(set) var isRecording = false

    /// Current audio level. Updated from tap callback.
    var onLevelUpdate: ((Float) -> Void)?

    init() {
        preWarm(deviceID: nil)
    }

    deinit {
        preparationTask?.cancel()
        cleanup()
    }

    // MARK: - Pre-warming

    /// Pre-warm AVAudioEngine in background to avoid 50-100ms latency on first use.
    private func preWarm(deviceID: AudioDeviceID?) {
        preparationTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                try self.prepareEngine(deviceID: deviceID)
                await MainActor.run { self.isPreWarmed = true }
                self.logger.info("AVAudioEngine pre-warmed")
            } catch {
                self.logger.error("Pre-warm failed: \(error, privacy: .public)")
            }
        }
    }

    private func prepareEngine(deviceID: AudioDeviceID?) throws {
        let engine = AVAudioEngine()

        // Set specific input device if requested
        if let deviceID {
            let audioUnit = engine.inputNode.audioUnit!
            var devID = deviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &devID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                logger.error("Failed to set input device \(deviceID): \(status)")
                // Fall through — will use default device
            } else {
                logger.info("Set input device to ID \(deviceID)")
            }
        }

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
        self.preparedDeviceID = deviceID

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
    /// If `deviceID` is provided, captures from that specific input device.
    func start(outputURL: URL, tapStreamDescription: AudioStreamBasicDescription? = nil, deviceID: AudioDeviceID? = nil) throws {
        guard !isRecording else { return }

        waitForPreWarm()

        // Re-prepare engine if device changed or engine wasn't pre-warmed
        if audioEngine == nil || preparedDeviceID != deviceID {
            cleanup()
            try prepareEngine(deviceID: deviceID)
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
