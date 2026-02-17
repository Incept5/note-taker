import Foundation
import AudioToolbox
import OSLog

/// Represents an audio input device.
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool
}

/// Enumerates audio input devices and listens for hot-plug changes.
@MainActor
final class AudioDeviceManager: ObservableObject {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "AudioDeviceManager")

    @Published private(set) var inputDevices: [AudioInputDevice] = []

    /// The UID of the user-selected input device, or nil for system default.
    @Published var selectedInputDeviceUID: String? {
        didSet {
            UserDefaults.standard.set(selectedInputDeviceUID, forKey: "selectedInputDeviceUID")
        }
    }

    /// The resolved AudioDeviceID for the current selection, or nil to use system default.
    var selectedDeviceID: AudioDeviceID? {
        guard let uid = selectedInputDeviceUID else { return nil }
        return inputDevices.first(where: { $0.uid == uid })?.id
    }

    /// Stored outside actor isolation so deinit can access it.
    private nonisolated(unsafe) var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        selectedInputDeviceUID = UserDefaults.standard.string(forKey: "selectedInputDeviceUID")
        refreshDevices()
        installDeviceChangeListener()
    }

    deinit {
        guard let block = listenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID.system, &address, DispatchQueue.main, block)
    }

    // MARK: - Device Enumeration

    func refreshDevices() {
        do {
            let defaultID = try AudioObjectID.readDefaultInputDevice()
            let deviceIDs = try Self.readAllInputDevices()

            inputDevices = deviceIDs.compactMap { deviceID in
                guard let name = try? deviceID.readDeviceName(),
                      let uid = try? deviceID.readDeviceUID() else {
                    return nil
                }
                return AudioInputDevice(
                    id: deviceID,
                    uid: uid,
                    name: name,
                    isDefault: deviceID == defaultID
                )
            }

            logger.info("Found \(self.inputDevices.count) input devices")

            // If saved device is no longer available, clear selection (will use default)
            if let selected = selectedInputDeviceUID,
               !inputDevices.contains(where: { $0.uid == selected }) {
                logger.warning("Previously selected device '\(selected)' no longer available")
            }
        } catch {
            logger.error("Failed to enumerate input devices: \(error, privacy: .public)")
        }
    }

    // MARK: - Device Change Listener

    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }
        self.listenerBlock = block

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID.system,
            &address,
            DispatchQueue.main,
            block
        )

        if status != noErr {
            logger.error("Failed to install device change listener: \(status)")
        }
    }


    // MARK: - Core Audio Helpers

    private static func readAllInputDevices() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(AudioObjectID.system, &address, 0, nil, &dataSize)
        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Error reading device list size: \(err)")
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: AudioObjectID.unknown, count: count)
        err = AudioObjectGetPropertyData(AudioObjectID.system, &address, 0, nil, &dataSize, &deviceIDs)
        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Error reading device list: \(err)")
        }

        // Filter to devices that have input channels
        return deviceIDs.filter { $0.hasInputChannels() }
    }
}

// MARK: - AudioObjectID extensions for input devices

extension AudioObjectID {
    static func readDefaultInputDevice() throws -> AudioDeviceID {
        try AudioDeviceID.system.read(
            kAudioHardwarePropertyDefaultInputDevice,
            defaultValue: AudioDeviceID.unknown
        )
    }

    func readDeviceName() throws -> String {
        try readString(kAudioObjectPropertyName)
    }

    func hasInputChannels() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let err2 = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, bufferListPointer)
        guard err2 == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        let totalChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
        return totalChannels > 0
    }
}
