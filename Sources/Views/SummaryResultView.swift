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
                    // Overview
                    let overviewText = summary.effectiveOverview
                    if !overviewText.isEmpty {
                        sectionCard("Overview", icon: "doc.plaintext", color: .secondary) {
                            Text(overviewText)
                                .font(.system(.body, design: .default))
                                .textSelection(.enabled)
                        }
                    }

                    // Key Decisions
                    let decisions = summary.effectiveKeyDecisions
                    if !decisions.isEmpty {
                        sectionCard("Key Decisions", icon: "checkmark.seal.fill", color: .green) {
                            ForEach(decisions, id: \.self) { decision in
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

                    // Discussion Highlights
                    let highlights = summary.effectiveDiscussionHighlights
                    if !highlights.isEmpty && summary.isNewFormat {
                        sectionCard("Discussion Highlights", icon: "bubble.left.and.bubble.right", color: .blue) {
                            ForEach(Array(highlights.enumerated()), id: \.offset) { _, topic in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(topic.topic)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.blue)
                                    Text(topic.detail)
                                        .font(.system(.body, design: .default))
                                        .textSelection(.enabled)
                                }
                                .padding(.bottom, 4)
                            }
                        }
                    }

                    // Blockers
                    let blockers = summary.effectiveBlockers
                    if !blockers.isEmpty {
                        sectionCard("Blockers", icon: "exclamationmark.triangle", color: .red) {
                            ForEach(blockers, id: \.self) { blocker in
                                bulletItem(blocker, color: .red)
                            }
                        }
                    }

                    // Next Steps
                    let steps = summary.effectiveNextSteps
                    if !steps.isEmpty {
                        sectionCard("Next Steps", icon: "arrow.forward.circle", color: .purple) {
                            ForEach(steps, id: \.self) { step in
                                bulletItem(step, color: .purple)
                            }
                        }
                    }

                    // Speaker Contributions
                    if let attributions = summary.speakerAttributions, !attributions.isEmpty {
                        sectionCard("Speaker Contributions", icon: "person.2", color: .cyan) {
                            ForEach(attributions.keys.sorted(), id: \.self) { name in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name)
                                        .font(.caption.bold())
                                        .foregroundStyle(.cyan)
                                    if let contributions = attributions[name] {
                                        ForEach(contributions, id: \.self) { contribution in
                                            bulletItem(contribution, color: .cyan)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Open Questions (old format fallback)
                    let questions = summary.effectiveOpenQuestions
                    if !questions.isEmpty && !summary.isNewFormat {
                        sectionCard("Open Questions", icon: "questionmark.circle", color: .purple) {
                            ForEach(questions, id: \.self) { question in
                                bulletItem(question, color: .purple)
                            }
                        }
                    }

                    // Key Points (old format fallback)
                    if !summary.isNewFormat, let keyPoints = summary.keyPoints, !keyPoints.isEmpty {
                        sectionCard("Key Points", icon: "list.bullet", color: .blue) {
                            ForEach(keyPoints, id: \.self) { point in
                                bulletItem(point, color: .blue)
                            }
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
