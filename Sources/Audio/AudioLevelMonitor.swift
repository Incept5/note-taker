import AVFoundation

enum AudioLevelMonitor {
    /// Calculate normalized audio level (0..1) from a PCM buffer.
    /// Uses peak detection across all channels, converted to dB, then normalized.
    static func peakLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let floatData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var maxSample: Float = 0

        for channel in 0..<channelCount {
            let channelData = floatData[channel]
            for frame in 0..<frameLength {
                let sample = abs(channelData[frame])
                if sample > maxSample {
                    maxSample = sample
                }
            }
        }

        return normalizeToLevel(peak: maxSample)
    }

    /// Convert raw peak amplitude to normalized 0..1 level.
    /// Maps -60 dB..0 dB range to 0..1.
    private static func normalizeToLevel(peak: Float) -> Float {
        guard peak > 0 else { return 0 }
        let db = 20 * log10(peak)
        let minDB: Float = -60
        let normalized = (db - minDB) / (0 - minDB)
        return min(max(normalized, 0), 1)
    }
}
