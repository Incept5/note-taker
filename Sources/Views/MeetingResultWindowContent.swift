import SwiftUI

struct MeetingResultWindowContent: View {
    let summary: MeetingSummary
    let transcript: String
    let duration: String
    let onNewRecording: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            Divider()

            // Two-pane content
            HSplitView {
                summaryPane
                    .frame(minWidth: 300)
                transcriptPane
                    .frame(minWidth: 250)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Metadata
            HStack(spacing: 12) {
                Label(duration, systemImage: "clock")
                Label(summary.modelUsed, systemImage: "cpu")
                Label(formatTime(summary.processingDuration), systemImage: "timer")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button("Copy Summary") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary.markdownText(), forType: .string)
                }

                Button("Copy Transcript") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript, forType: .string)
                }

                Button("New Recording") {
                    onNewRecording()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Summary Pane

    private var summaryPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Overview
                let overviewText = summary.effectiveOverview
                if !overviewText.isEmpty {
                    sectionView("Overview") {
                        summaryParagraphs(overviewText)
                    }
                }

                // Key Decisions
                let decisions = summary.effectiveKeyDecisions
                if !decisions.isEmpty {
                    sectionView("Key Decisions") {
                        ForEach(decisions, id: \.self) { decision in
                            bulletItem(decision, icon: "checkmark.diamond.fill", color: .green)
                        }
                    }
                }

                // Action Items
                if !summary.actionItems.isEmpty {
                    sectionView("Action Items") {
                        ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.orange)
                                    .font(.body)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.task)
                                        .font(.body)
                                        .textSelection(.enabled)
                                    if let owner = item.owner, !owner.isEmpty {
                                        Text("Owner: \(owner)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                // Discussion Highlights
                let highlights = summary.effectiveDiscussionHighlights
                if !highlights.isEmpty && summary.isNewFormat {
                    sectionView("Discussion Highlights") {
                        ForEach(Array(highlights.enumerated()), id: \.offset) { _, topic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.topic)
                                    .font(.body.bold())
                                    .foregroundStyle(.blue)
                                Text(topic.detail)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }

                // Blockers
                let blockers = summary.effectiveBlockers
                if !blockers.isEmpty {
                    sectionView("Blockers") {
                        ForEach(blockers, id: \.self) { blocker in
                            bulletItem(blocker, icon: "exclamationmark.triangle.fill", color: .red)
                        }
                    }
                }

                // Next Steps
                let steps = summary.effectiveNextSteps
                if !steps.isEmpty {
                    sectionView("Next Steps") {
                        ForEach(steps, id: \.self) { step in
                            bulletItem(step, icon: "arrow.forward.circle.fill", color: .purple)
                        }
                    }
                }

                // Open Questions (old format)
                let questions = summary.effectiveOpenQuestions
                if !questions.isEmpty && !summary.isNewFormat {
                    sectionView("Open Questions") {
                        ForEach(questions, id: \.self) { question in
                            bulletItem(question, icon: "questionmark.circle.fill", color: .purple)
                        }
                    }
                }

                // Key Points (old format only)
                if !summary.isNewFormat, let keyPoints = summary.keyPoints, !keyPoints.isEmpty {
                    sectionView("Key Points") {
                        ForEach(keyPoints, id: \.self) { point in
                            bulletItem(point, icon: "circle.fill", color: .blue)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    /// Render summary text as separate paragraphs split on double-newlines.
    @ViewBuilder
    private func summaryParagraphs(_ text: String) -> some View {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count > 1 {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.body)
                    .textSelection(.enabled)
            }
        } else {
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    // MARK: - Transcript Pane

    private var transcriptPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Transcript")
                    .font(.title2.bold())

                Text(transcript)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    // MARK: - Helpers

    private func sectionView<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func bulletItem(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
                .frame(width: 14, alignment: .center)
                .padding(.top, 3)
            Text(text)
                .font(.body)
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
