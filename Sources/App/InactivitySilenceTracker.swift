import Foundation

/// Decides when a recording should auto-stop after prolonged silence.
///
/// Counts *consecutive* silent seconds: any audio above the silence threshold resets
/// the count, so the recording only stops when it has been genuinely idle for the full
/// timeout. Pure value type with no dependencies — exercised directly in unit tests.
struct InactivitySilenceTracker {
    /// Auto-stop after this many minutes of continuous silence. 0 disables auto-stop.
    let timeoutMinutes: Int
    /// Audio level (0..1) below this is considered silence.
    let silenceLevelThreshold: Float

    private(set) var consecutiveSilentSeconds: Int = 0

    init(timeoutMinutes: Int, silenceLevelThreshold: Float) {
        self.timeoutMinutes = timeoutMinutes
        self.silenceLevelThreshold = silenceLevelThreshold
    }

    /// Whether auto-stop is active. When false, `registerSecond` never fires.
    var isEnabled: Bool { timeoutMinutes > 0 }

    /// Number of continuous silent seconds required to trigger an auto-stop.
    var timeoutSeconds: Int { timeoutMinutes * 60 }

    mutating func reset() {
        consecutiveSilentSeconds = 0
    }

    /// Feed one second's audio level. Returns `true` when the recording should auto-stop.
    mutating func registerSecond(level: Float) -> Bool {
        guard isEnabled else { return false }
        if level < silenceLevelThreshold {
            consecutiveSilentSeconds += 1
        } else {
            consecutiveSilentSeconds = 0
        }
        return consecutiveSilentSeconds >= timeoutSeconds
    }
}
