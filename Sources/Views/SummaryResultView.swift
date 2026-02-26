import SwiftUI

struct SummaryResultView: View {
    let summary: MeetingSummary
    let audio: CapturedAudio
    let transcription: MeetingTranscription
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
                VStack(alignment: .leading, spacing: 16) {
                    // Key Points
                    if !summary.keyPoints.isEmpty {
                        sectionCard("Key Points", icon: "list.bullet", color: .blue) {
                            ForEach(summary.keyPoints, id: \.self) { point in
                                bulletItem(point, color: .blue)
                            }
                        }
                    }

                    // Decisions
                    if !summary.decisions.isEmpty {
                        sectionCard("Decisions", icon: "checkmark.seal.fill", color: .green) {
                            ForEach(summary.decisions, id: \.self) { decision in
                                bulletItem(decision, color: .green)
                            }
                        }
                    }

                    // Action Items
                    if !summary.actionItems.isEmpty {
                        sectionCard("Action Items", icon: "checklist", color: .orange) {
                            ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "circle")
                                        .foregroundStyle(.orange)
                                        .font(.system(size: 8))
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.task)
                                            .font(.system(.body, design: .default))
                                        if let owner = item.owner, !owner.isEmpty, owner.lowercased() != "null" {
                                            Text("Owner: \(owner)")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Open Questions
                    if !summary.openQuestions.isEmpty {
                        sectionCard("Open Questions", icon: "questionmark.circle", color: .purple) {
                            ForEach(summary.openQuestions, id: \.self) { question in
                                bulletItem(question, color: .purple)
                            }
                        }
                    }

                    // Full Summary
                    if !summary.summary.isEmpty {
                        sectionCard("Full Summary", icon: "doc.plaintext", color: .secondary) {
                            Text(summary.summary)
                                .font(.system(.body, design: .default))
                                .textSelection(.enabled)
                        }
                    }

                    // Transcript
                    DisclosureGroup {
                        SegmentedTranscriptView(speakerSegments: transcription.interleavedSpeakerSegments())
                    } label: {
                        Label("Transcript", systemImage: "text.alignleft")
                            .font(.caption.bold())
                            .foregroundStyle(.teal)
                            .textCase(.uppercase)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .frame(maxHeight: 350)

            Divider()

            HStack(spacing: 8) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary.markdownText(), forType: .string)
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

    @ViewBuilder
    private func sectionCard<Content: View>(
        _ title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(color)
                .textCase(.uppercase)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func bulletItem(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .foregroundStyle(color.opacity(0.6))
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
}
