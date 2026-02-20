import AudioToolbox
import AVFoundation
import OSLog
import ScreenCaptureKit

// MARK: - MicRingBuffer

/// Thread-safe circular buffer for mic audio samples.
/// Written to from AVAudioEngine's mic tap callback, read from SCStream's audio callback.
private final class MicRingBuffer {
    private let lock = NSLock()
    private var buffer: [Float]
    private let capacity: Int
    private var writeIndex = 0
    private var availableCount = 0

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Append mono mic samples into the ring buffer.
    func write(_ samples: UnsafePointer<Float>, count: Int) {
        lock.lock()
        defer { lock.unlock() }

        for i in 0..<count {
            buffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
        }
        availableCount = min(availableCount + count, capacity)
    }

    /// Read and remove up to `count` samples, mixing (adding) them into `destination`.
    /// Writes mono mic samples into each channel of the non-interleaved stereo buffer.
    func mixInto(channelData: [UnsafeMutablePointer<Float>], channelCount: Int, frameCount: Int) {
        lock.lock()
        defer { lock.unlock() }

        let samplesToMix = min(frameCount, availableCount)
        guard samplesToMix > 0 else { return }

        // Calculate read start position
        let readStart = (writeIndex - availableCount + capacity) % capacity

        for i in 0..<samplesToMix {
            let idx = (readStart + i) % capacity
            let sample = buffer[idx]
            // Mix mono mic into all stereo channels
            for ch in 0..<channelCount {
                channelData[ch][i] += sample
            }
        }
        availableCount -= samplesToMix
    }
}

// MARK: - ScreenCaptureAudioRecorder

/// Captures system audio using ScreenCaptureKit's SCStream (audio-only mode).
/// On macOS 15+, mic audio is mixed in natively via `captureMicrophone = true`.
/// On macOS 14.x, mic audio is captured separately via AVAudioEngine and mixed
/// into the system audio stream in the SCStream callback.
final class ScreenCaptureAudioRecorder: NSObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "ScreenCaptureAudioRecorder")
    private let queue = DispatchQueue(label: "com.incept5.NoteTaker.SCStreamAudio", qos: .userInitiated)

    let fileURL: URL
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?

    // Mic mixing (macOS 14.x fallback)
    private var micEngine: AVAudioEngine?
    private var micRingBuffer: MicRingBuffer?

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
    /// - Parameters:
    ///   - micEnabled: Whether to mix microphone audio into the system stream.
    ///   - micDeviceUID: UID of the mic input device to use, or nil for system default.
    func start(micEnabled: Bool = true, micDeviceUID: String? = nil) async throws {
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

        // Explicitly disable native mic capture — we handle mic mixing ourselves
        // via AVAudioEngine + ring buffer for consistent behavior and device selection
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

        // Start mic capture via AVAudioEngine when enabled
        if micEnabled {
            startMicEngine(deviceUID: micDeviceUID)
        }

        logger.info("System audio capture started → \(self.fileURL.lastPathComponent)")
    }

    /// Start AVAudioEngine to capture mic input and feed samples into the ring buffer.
    /// Mic samples are mixed into the system audio stream in the SCStream callback.
    private func startMicEngine(deviceUID: String? = nil) {
        let engine = AVAudioEngine()

        // Select specific input device if requested
        if let deviceUID {
            let inputUnit = engine.inputNode.audioUnit!
            var deviceID = deviceIDForUID(deviceUID)
            if deviceID != kAudioObjectUnknown {
                let status = AudioUnitSetProperty(
                    inputUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &deviceID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status != noErr {
                    logger.warning("Failed to set mic device \(deviceUID): \(status) — using default")
                }
            }
        }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            logger.warning("No mic input available — skipping mic mixing")
            return
        }

        // Ring buffer: ~4 seconds at 48kHz
        let ringBuffer = MicRingBuffer(capacity: 192_000)

        // Target format: 48kHz mono float32 (matches system audio sample rate)
        let targetRate: Double = 48_000
        let targetFormat = AVAudioFormat(standardFormatWithSampleRate: targetRate, channels: 1)!

        // Do we need sample rate conversion?
        let needsConversion = abs(hwFormat.sampleRate - targetRate) > 1.0 || hwFormat.channelCount != 1
        var converter: AVAudioConverter?

        if needsConversion {
            converter = AVAudioConverter(from: hwFormat, to: targetFormat)
            if converter == nil {
                logger.warning("Cannot create mic format converter (\(hwFormat.sampleRate)Hz \(hwFormat.channelCount)ch → 48kHz mono) — skipping mic mixing")
                return
            }
        }

        let capturedLogger = self.logger

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak ringBuffer] buffer, _ in
            guard let ringBuffer else { return }

            if let converter {
                // Convert to 48kHz mono
                let frameCapacity = AVAudioFrameCount(
                    Double(buffer.frameLength) * targetRate / buffer.format.sampleRate
                ) + 1
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

                var error: NSError?
                var inputConsumed = false
                converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    if inputConsumed {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    inputConsumed = true
                    outStatus.pointee = .haveData
                    return buffer
                }
                if let error {
                    capturedLogger.warning("Mic conversion error: \(error, privacy: .public)")
                    return
                }
                if let data = convertedBuffer.floatChannelData, convertedBuffer.frameLength > 0 {
                    ringBuffer.write(data[0], count: Int(convertedBuffer.frameLength))
                }
            } else {
                // Already 48kHz mono — write directly
                if let data = buffer.floatChannelData, buffer.frameLength > 0 {
                    ringBuffer.write(data[0], count: Int(buffer.frameLength))
                }
            }
        }

        do {
            try engine.start()
            self.micEngine = engine
            self.micRingBuffer = ringBuffer
            logger.info("Mic engine started for audio mixing (hw: \(hwFormat.sampleRate)Hz \(hwFormat.channelCount)ch, conversion: \(needsConversion))")
        } catch {
            logger.error("Failed to start mic engine: \(error, privacy: .public)")
            inputNode.removeTap(onBus: 0)
        }
    }

    /// Look up an AudioDeviceID from a device UID string.
    private func deviceIDForUID(_ uid: String) -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var cfUID = uid as CFString
        let qualifierSize = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                qualifierSize,
                uidPtr,
                &dataSize,
                &deviceID
            )
        }

        if status != noErr {
            logger.warning("Could not translate UID '\(uid)' to device ID: \(status)")
            return AudioDeviceID(kAudioObjectUnknown)
        }
        return deviceID
    }

    func stop() {
        guard isRecording else { return }

        logger.debug("Stopping system audio capture")

        isRecording = false

        // Stop mic engine (macOS 14.x path)
        if let engine = micEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            micEngine = nil
            micRingBuffer = nil
            logger.debug("Mic engine stopped")
        }

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

        // Mix mic audio into system buffer (macOS 14.x path only)
        if let ringBuffer = micRingBuffer, let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var channels = [UnsafeMutablePointer<Float>]()
            for ch in 0..<channelCount {
                channels.append(channelData[ch])
            }
            ringBuffer.mixInto(channelData: channels, channelCount: channelCount, frameCount: Int(buffer.frameLength))
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
