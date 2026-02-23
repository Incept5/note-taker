import Foundation

struct MeetingTranscription: Codable {
    let systemTranscript: TimestampedTranscript
    let micTranscript: TimestampedTranscript?
    let combinedText: String
    let processingDuration: TimeInterval
    let modelUsed: String

    /// Interleave system ("Others") and mic ("You") segments chronologically.
    /// Falls back to system-only segments when no mic transcript exists.
    func interleavedSpeakerSegments() -> [SpeakerSegment] {
        guard let mic = micTranscript, !mic.fullText.isEmpty else {
            return systemTranscript.segments.map { SpeakerSegment(speaker: "", segment: $0) }
        }

        let others = systemTranscript.segments.map { SpeakerSegment(speaker: "Others", segment: $0) }
        let you = mic.segments.map { SpeakerSegment(speaker: "You", segment: $0) }

        return (others + you).sorted { $0.segment.startTime < $1.segment.startTime }
    }
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
