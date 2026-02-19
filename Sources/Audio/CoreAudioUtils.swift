import Foundation
import AudioToolbox

// MARK: - AudioCaptureError

enum AudioCaptureError: LocalizedError {
    case coreAudioError(String)
    case invalidProcessID(pid_t)
    case invalidSystemObject
    case microphonePermissionDenied
    case noAudioFormat
    case recordingFailed(String)
    case screenCaptureNotAvailable(String)
    case streamStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .coreAudioError(let message):
            "Core Audio Error: \(message)"
        case .invalidProcessID(let pid):
            "Invalid process identifier: \(pid)"
        case .invalidSystemObject:
            "Only supported for the system audio object"
        case .microphonePermissionDenied:
            "Microphone permission denied. Grant access in System Settings > Privacy & Security > Microphone."
        case .noAudioFormat:
            "Audio format not available"
        case .recordingFailed(let message):
            "Recording failed: \(message)"
        case .screenCaptureNotAvailable(let message):
            "Screen Recording permission required: \(message)"
        case .streamStartFailed(let message):
            "Audio capture failed: \(message)"
        }
    }
}

// MARK: - AudioObjectID Extensions

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown

    var isUnknown: Bool { self == .unknown }
    var isValid: Bool { !isUnknown }
}

// MARK: - System-level reads (static)

extension AudioObjectID {
    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioDeviceID.system.readDefaultSystemOutputDevice()
    }

    static func readProcessList() throws -> [AudioObjectID] {
        try AudioObjectID.system.readProcessList()
    }

    static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try AudioDeviceID.system.translatePIDToProcessObjectID(pid: pid)
    }
}

// MARK: - Instance property reads

extension AudioObjectID {
    func readProcessList() throws -> [AudioObjectID] {
        try requireSystemObject()

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Error reading process list data size: \(err)")
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var value = [AudioObjectID](repeating: .unknown, count: count)
        err = AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, &value)
        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Error reading process list: \(err)")
        }

        return value
    }

    func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try requireSystemObject()
        return try read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
        try requireSystemObject()

        let processObject = try read(
            kAudioHardwarePropertyTranslatePIDToProcessObject,
            defaultValue: AudioObjectID.unknown,
            qualifier: pid
        )

        guard processObject.isValid else {
            throw AudioCaptureError.invalidProcessID(pid)
        }

        return processObject
    }

    func readDeviceUID() throws -> String {
        try readString(kAudioDevicePropertyDeviceUID)
    }

    func readProcessBundleID() -> String? {
        guard let result = try? readString(kAudioProcessPropertyBundleID) else { return nil }
        return result.isEmpty ? nil : result
    }

    func readProcessPID() throws -> pid_t {
        try read(kAudioProcessPropertyPID, defaultValue: pid_t(-1))
    }

    func readProcessIsRunning() -> Bool {
        (try? readBool(kAudioProcessPropertyIsRunning)) ?? false
    }

    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    private func requireSystemObject() throws {
        guard self == .system else {
            throw AudioCaptureError.invalidSystemObject
        }
    }
}

// MARK: - Generic property read helpers

extension AudioObjectID {
    func read<T, Q>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T,
        qualifier: Q
    ) throws -> T {
        var inQualifier = qualifier
        let qualifierSize = UInt32(MemoryLayout<Q>.size(ofValue: qualifier))
        return try withUnsafeMutablePointer(to: &inQualifier) { qualifierPtr in
            try readProperty(
                AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
                defaultValue: defaultValue,
                qualifierSize: qualifierSize,
                qualifierData: qualifierPtr
            )
        }
    }

    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) throws -> T {
        try readProperty(
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element),
            defaultValue: defaultValue,
            qualifierSize: 0,
            qualifierData: nil
        )
    }

    func readString(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> String {
        let address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        let cfString: CFString = try readProperty(address, defaultValue: "" as CFString, qualifierSize: 0, qualifierData: nil)
        return cfString as String
    }

    func readBool(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) throws -> Bool {
        let value: UInt32 = try read(selector, scope: scope, element: element, defaultValue: 0)
        return value != 0
    }

    private func readProperty<T>(
        _ inAddress: AudioObjectPropertyAddress,
        defaultValue: T,
        qualifierSize: UInt32,
        qualifierData: UnsafeRawPointer?
    ) throws -> T {
        var address = inAddress
        var dataSize: UInt32 = 0

        var err = AudioObjectGetPropertyDataSize(self, &address, qualifierSize, qualifierData, &dataSize)
        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Error reading property data size: \(err)")
        }

        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, qualifierSize, qualifierData, &dataSize, ptr)
        }

        guard err == noErr else {
            throw AudioCaptureError.coreAudioError("Error reading property data: \(err)")
        }

        return value
    }
}
