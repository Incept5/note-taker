import SwiftUI

/// A tagged segment carrying a speaker label alongside the transcript data.
struct SpeakerSegment {
    let speaker: String
    let segment: TranscriptSegment
}

struct SegmentedTranscriptView: View {
    let segments: [SpeakerSegment]

    /// Seconds per paragraph group — segments are grouped into time windows of this size
    private let paragraphInterval: TimeInterval = 10.0

    /// Gap between consecutive segments that indicates a speaker change
    private let speakerChangeGap: TimeInterval = 2.0

    /// Convenience initialiser for a single-speaker (unlabelled) segment list.
    init(segments: [TranscriptSegment]) {
        self.segments = segments.map { SpeakerSegment(speaker: "", segment: $0) }
    }

    /// Full initialiser with speaker-tagged segments.
    init(speakerSegments: [SpeakerSegment]) {
        self.segments = speakerSegments
    }

    var body: some View {
        let paragraphs = buildParagraphs()

        if paragraphs.isEmpty {
            Text("No transcript segments")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, para in
                    VStack(alignment: .leading, spacing: 4) {
                        if index > 0 {
                            Divider()
                                .padding(.bottom, 2)
                        }

                        // Timestamp pill + speaker label
                        HStack(spacing: 6) {
                            Text(formatTime(para.startTime))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(pillColor(for: para.speaker).opacity(0.7), in: Capsule())

                            if !para.speaker.isEmpty {
                                Text(para.speaker)
                                    .font(.caption2.bold())
                                    .foregroundStyle(pillColor(for: para.speaker))
                            }
                        }

                        // Paragraph text
                        Text(para.text)
                            .font(.callout)
                            .textSelection(.enabled)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    private func buildParagraphs() -> [TranscriptParagraph] {
        guard let first = segments.first else { return [] }

        var paragraphs: [TranscriptParagraph] = []
        var currentTexts: [String] = []
        var windowStart = first.segment.startTime
        var currentSpeaker = first.speaker

        for (i, tagged) in segments.enumerated() {
            let text = tagged.segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let speakerChanged = tagged.speaker != currentSpeaker
            let hasSpeakerGap = i > 0 && (tagged.segment.startTime - segments[i - 1].segment.endTime) >= speakerChangeGap
            let timeExceeded = tagged.segment.startTime - windowStart >= paragraphInterval

            // Start a new paragraph on: time window exceeded, speaker label change, or gap-based speaker change
            if (timeExceeded || speakerChanged || hasSpeakerGap) && !currentTexts.isEmpty {
                paragraphs.append(TranscriptParagraph(
                    startTime: windowStart,
                    text: currentTexts.joined(separator: " "),
                    speaker: currentSpeaker
                ))
                currentTexts = []
                windowStart = tagged.segment.startTime
                currentSpeaker = tagged.speaker
            } else if currentTexts.isEmpty {
                currentSpeaker = tagged.speaker
            }

            currentTexts.append(text)
        }

        // Flush remaining
        if !currentTexts.isEmpty {
            paragraphs.append(TranscriptParagraph(
                startTime: windowStart,
                text: currentTexts.joined(separator: " "),
                speaker: currentSpeaker
            ))
        }

        return paragraphs
    }

    private func pillColor(for speaker: String) -> Color {
        switch speaker {
        case "You": return .green
        case "Others": return .blue
        default: return .blue
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct TranscriptParagraph {
    let startTime: TimeInterval
    let text: String
    let speaker: String
}
