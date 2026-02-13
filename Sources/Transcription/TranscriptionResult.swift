import Foundation

struct MeetingTranscription {
    let systemTranscript: TimestampedTranscript
    let micTranscript: TimestampedTranscript?
    let combinedText: String
    let processingDuration: TimeInterval
    let modelUsed: String
}

struct TimestampedTranscript {
    let segments: [TranscriptSegment]
    let fullText: String
}

struct TranscriptSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
