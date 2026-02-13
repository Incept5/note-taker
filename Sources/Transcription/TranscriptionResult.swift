import Foundation

struct MeetingTranscription: Codable {
    let systemTranscript: TimestampedTranscript
    let micTranscript: TimestampedTranscript?
    let combinedText: String
    let processingDuration: TimeInterval
    let modelUsed: String
}

struct TimestampedTranscript: Codable {
    let segments: [TranscriptSegment]
    let fullText: String
}

struct TranscriptSegment: Codable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
