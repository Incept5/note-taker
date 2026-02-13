import SwiftUI

struct SummaryResultView: View {
    let summary: MeetingSummary
    let audio: CapturedAudio
    let transcription: MeetingTranscription
    let onViewTranscript: () -> Void
    let onRegenerate: () -> Void
    let onNewRecording: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32))
                .foregroundStyle(.purple)

            Text("Meeting Summary")
                .font(.headline)

            HStack(spacing: 16) {
                Label(audio.formattedDuration, systemImage: "clock")
                Label(summary.modelUsed, systemImage: "cpu")
                Label(formatTime(summary.processingDuration), systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Summary
                    sectionHeader("Summary")
                    Text(summary.summary)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)

                    // Key Points
                    if !summary.keyPoints.isEmpty {
                        sectionHeader("Key Points")
                        ForEach(summary.keyPoints, id: \.self) { point in
                            bulletItem(point)
                        }
                    }

                    // Decisions
                    if !summary.decisions.isEmpty {
                        sectionHeader("Decisions")
                        ForEach(summary.decisions, id: \.self) { decision in
                            bulletItem(decision)
                        }
                    }

                    // Action Items
                    if !summary.actionItems.isEmpty {
                        sectionHeader("Action Items")
                        ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task)
                                        .font(.system(.body, design: .default))
                                    if let owner = item.owner, !owner.isEmpty {
                                        Text("Owner: \(owner)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Open Questions
                    if !summary.openQuestions.isEmpty {
                        sectionHeader("Open Questions")
                        ForEach(summary.openQuestions, id: \.self) { question in
                            bulletItem(question)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .frame(maxHeight: 250)

            Divider()

            HStack(spacing: 8) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(formattedText, forType: .string)
                }

                Button("Transcript") {
                    onViewTranscript()
                }

                Button("Regenerate") {
                    onRegenerate()
                }

                Button("New Recording") {
                    onNewRecording()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 12)
        }
        .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func bulletItem(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.body, design: .default))
                .textSelection(.enabled)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }

    private var formattedText: String {
        var text = "## Summary\n\(summary.summary)\n"

        if !summary.keyPoints.isEmpty {
            text += "\n## Key Points\n"
            for point in summary.keyPoints {
                text += "- \(point)\n"
            }
        }

        if !summary.decisions.isEmpty {
            text += "\n## Decisions\n"
            for decision in summary.decisions {
                text += "- \(decision)\n"
            }
        }

        if !summary.actionItems.isEmpty {
            text += "\n## Action Items\n"
            for item in summary.actionItems {
                let owner = item.owner.map { " (@\($0))" } ?? ""
                text += "- [ ] \(item.task)\(owner)\n"
            }
        }

        if !summary.openQuestions.isEmpty {
            text += "\n## Open Questions\n"
            for question in summary.openQuestions {
                text += "- \(question)\n"
            }
        }

        return text
    }
}
