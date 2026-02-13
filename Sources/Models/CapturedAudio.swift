import Foundation

struct CapturedAudio {
    let systemAudioURL: URL
    let microphoneURL: URL
    let directory: URL
    let startedAt: Date
    let duration: TimeInterval

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
