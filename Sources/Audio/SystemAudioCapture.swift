import AudioToolbox
import AVFoundation
import OSLog

// MARK: - SystemAudioTap

/// Manages the lifecycle of a Core Audio process tap: create tap → build aggregate device → run IO proc.
/// Cleanup order is critical: stop device → destroy IO proc → destroy aggregate device → destroy tap.
final class SystemAudioTap {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "SystemAudioTap")

    private let process: AudioProcess

    private var processTapID: AudioObjectID = .unknown
    private var aggregateDeviceID: AudioObjectID = .unknown
    private var deviceProcID: AudioDeviceIOProcID?

    private(set) var tapStreamDescription: AudioStreamBasicDescription?
    private(set) var activated = false

    init(process: AudioProcess) {
        self.process = process
    }

    /// Activate the tap. Must be called on the main actor (Core Audio Tap APIs require it).
    @MainActor
    func activate() throws {
        guard !activated else { return }

        logger.debug("Activating tap for \(self.process.name, privacy: .public)")

        let tapDescription = CATapDescription(stereoMixdownOfProcesses: [process.objectID])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted

        var tapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard err == noErr else {
            throw AudioCaptureError.tapCreationFailed(err)
        }

        logger.debug("Created process tap #\(tapID, privacy: .public)")
        self.processTapID = tapID

        // Read the tap's stream format before creating the aggregate device
        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()

        // Build aggregate device combining system output + tap
        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        let aggregateUID = UUID().uuidString

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NoteTaker-Tap-\(process.id)",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
                ],
            ],
        ]

        var aggDeviceID = AudioObjectID.unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggDeviceID)
        guard err == noErr else {
            // Clean up the tap we already created
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = .unknown
            throw AudioCaptureError.deviceCreationFailed(err)
        }

        self.aggregateDeviceID = aggDeviceID
        self.activated = true

        logger.debug("Created aggregate device #\(aggDeviceID, privacy: .public)")
    }

    /// Start the IO proc on the aggregate device, delivering audio buffers to the given block.
    func run(on queue: DispatchQueue, ioBlock: @escaping AudioDeviceIOBlock) throws {
        guard activated else {
            throw AudioCaptureError.coreAudioError("Tap not activated")
        }

        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Failed to create device IO proc: \(err)")
        }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Failed to start audio device: \(err)")
        }

        logger.debug("IO proc running on aggregate device")
    }

    /// Tear down everything in the correct order.
    func invalidate() {
        guard activated else { return }
        defer { activated = false }

        logger.debug("Invalidating tap for \(self.process.name, privacy: .public)")

        // 1. Stop the device
        if aggregateDeviceID.isValid {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr {
                logger.warning("Failed to stop aggregate device: \(err, privacy: .public)")
            }

            // 2. Destroy IO proc
            if let procID = deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
                if err != noErr {
                    logger.warning("Failed to destroy IO proc: \(err, privacy: .public)")
                }
                deviceProcID = nil
            }

            // 3. Destroy aggregate device
            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err, privacy: .public)")
            }
            aggregateDeviceID = .unknown
        }

        // 4. Destroy tap
        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                logger.warning("Failed to destroy process tap: \(err, privacy: .public)")
            }
            processTapID = .unknown
        }

        tapStreamDescription = nil
    }

    deinit {
        invalidate()
    }
}

// MARK: - SystemAudioRecorder

/// Wraps a SystemAudioTap with file writing. Creates an AVAudioFile and writes PCM buffers from the IO proc.
final class SystemAudioRecorder {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "SystemAudioRecorder")
    private let queue = DispatchQueue(label: "com.incept5.NoteTaker.SystemAudioTap", qos: .userInitiated)

    let fileURL: URL
    private let tap: SystemAudioTap

    private var audioFile: AVAudioFile?
    private(set) var isRecording = false

    /// Current audio level, updated from the IO callback. Read from main actor for UI.
    var onLevelUpdate: ((Float) -> Void)?

    init(fileURL: URL, tap: SystemAudioTap) {
        self.fileURL = fileURL
        self.tap = tap
    }

    /// Start recording. The tap must already be activated.
    func start() throws {
        guard !isRecording else { return }

        guard var streamDescription = tap.tapStreamDescription else {
            throw AudioCaptureError.noAudioFormat
        }

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw AudioCaptureError.coreAudioError("Failed to create AVAudioFormat from tap stream description")
        }

        logger.info("Recording format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: !format.isInterleaved,
        ]

        let file = try AVAudioFile(
            forWriting: fileURL,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: format.isInterleaved
        )

        self.audioFile = file

        try tap.run(on: queue) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self, let currentFile = self.audioFile else { return }

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                return
            }

            do {
                try currentFile.write(from: buffer)
            } catch {
                self.logger.error("Write error: \(error, privacy: .public)")
            }

            let level = AudioLevelMonitor.peakLevel(from: buffer)
            self.onLevelUpdate?(level)
        }

        isRecording = true
        logger.info("System audio recording started → \(self.fileURL.lastPathComponent)")
    }

    func stop() {
        guard isRecording else { return }

        logger.debug("Stopping system audio recording")

        audioFile = nil
        isRecording = false
        tap.invalidate()
    }

    /// The tap's stream description, useful for synchronizing mic capture format.
    var tapStreamDescription: AudioStreamBasicDescription? {
        tap.tapStreamDescription
    }

    deinit {
        stop()
    }
}
