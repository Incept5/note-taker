import SwiftUI

struct HistoryWindowContent: View {
    @ObservedObject var appState: AppState
    @State private var selectedMeeting: MeetingRecord?

    var body: some View {
        if let meeting = selectedMeeting {
            HistoryWindowDetailView(
                appState: appState,
                meetingId: meeting.id,
                onBack: { selectedMeeting = nil }
            )
        } else {
            historyList
        }
    }

    private var historyList: some View {
        VStack(spacing: 0) {
            if appState.meetingStore.recentMeetings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.meetingStore.recentMeetings) { meeting in
                            Button(action: {
                                selectedMeeting = meeting
                            }) {
                                MeetingRow(meeting: meeting)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    try? appState.meetingStore.deleteMeeting(id: meeting.id)
                                    if selectedMeeting?.id == meeting.id {
                                        selectedMeeting = nil
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No meetings yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Recorded meetings will appear here")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// Detail view shown inside the history window (reuses MeetingDetailView layout).
private struct HistoryWindowDetailView: View {
    @ObservedObject var appState: AppState
    let meetingId: String
    let onBack: () -> Void

    @State private var copiedSummary = false
    @State private var copiedTranscript = false

    /// Live meeting record from the store, so it refreshes after re-summarization.
    private var meeting: MeetingRecord {
        appState.meetingStore.recentMeetings.first(where: { $0.id == meetingId })
            ?? MeetingRecord(id: meetingId, startedAt: .now, status: "unknown", createdAt: .now)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("History")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Spacer()

                VStack(spacing: 2) {
                    Text(meeting.appName ?? "Meeting")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Text(meeting.formattedDate)
                        Text("·")
                        Text(meeting.formattedDuration)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    if let dirURL = meeting.recordingDirectoryURL {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dirURL.path)
                        }
                    }

                    Divider()

                    Button("Delete Meeting", role: .destructive) {
                        try? appState.meetingStore.deleteMeeting(id: meeting.id)
                        onBack()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Side-by-side content
            HStack(spacing: 0) {
                // Left: Summary
                panelView(
                    title: "Summary",
                    copied: $copiedSummary,
                    hasContent: meeting.summaryJSON != nil,
                    onCopy: {
                        if let summary = meeting.decodedSummary() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(summary.markdownText(participants: meeting.decodedParticipants()), forType: .string)
                            copiedSummary = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedSummary = false
                            }
                        }
                    },
                    extraButtons: {
                        if meeting.combinedTranscript != nil {
                            if appState.reSummarizingMeetingId == meeting.id {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            } else {
                                Button(action: {
                                    appState.reSummarize(meeting: meeting)
                                }) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                        Text("Re-summarize")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.reSummarizingMeetingId != nil)
                            }
                        }
                    }
                ) {
                    if let summary = meeting.decodedSummary() {
                        summaryContent(summary)
                    } else {
                        emptyPanel("No summary available")
                    }
                }

                Divider()

                // Right: Transcript
                panelView(
                    title: "Full Transcript",
                    copied: $copiedTranscript,
                    hasContent: meeting.combinedTranscript != nil,
                    onCopy: {
                        if let text = meeting.combinedTranscript {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            copiedTranscript = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedTranscript = false
                            }
                        }
                    }
                ) {
                    if let transcription = meeting.decodedTranscription() {
                        transcriptContent(transcription)
                    } else if let transcript = meeting.combinedTranscript, !transcript.isEmpty {
                        Text(transcript)
                            .font(.callout)
                            .textSelection(.enabled)
                    } else {
                        emptyPanel("No transcript available")
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Panel

    private func panelView<Content: View, Extra: View>(
        title: String,
        copied: Binding<Bool>,
        hasContent: Bool,
        onCopy: @escaping () -> Void,
        @ViewBuilder extraButtons: () -> Extra = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                extraButtons()
                if hasContent {
                    Button(action: onCopy) {
                        HStack(spacing: 3) {
                            Image(systemName: copied.wrappedValue ? "checkmark" : "doc.on.doc")
                            if copied.wrappedValue {
                                Text("Copied")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(copied.wrappedValue ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Transcript Content

    @ViewBuilder
    private func transcriptContent(_ transcription: MeetingTranscription) -> some View {
        SegmentedTranscriptView(speakerSegments: transcription.interleavedSpeakerSegments())
    }

    // MARK: - Summary Content

    @ViewBuilder
    private func summaryContent(_ summary: MeetingSummary) -> some View {
        // Overview
        let overviewText = summary.effectiveOverview
        if !overviewText.isEmpty {
            sectionHeader("Overview")
            summaryParagraphs(overviewText)
        }

        // Key Decisions
        let decisions = summary.effectiveKeyDecisions
        if !decisions.isEmpty {
            sectionHeader("Key Decisions")
            ForEach(decisions, id: \.self) { decision in
                bulletPoint(decision)
            }
        }

        // Action Items
        if !summary.actionItems.isEmpty {
            sectionHeader("Action Items")
            ForEach(summary.actionItems, id: \.task) { item in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.task)
                            .font(.callout)
                        if let owner = item.owner {
                            Text(owner)
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }

        // Discussion Highlights
        let highlights = summary.effectiveDiscussionHighlights
        if !highlights.isEmpty && summary.isNewFormat {
            sectionHeader("Discussion Highlights")
            ForEach(Array(highlights.enumerated()), id: \.offset) { _, topic in
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.topic)
                        .font(.callout.bold())
                        .foregroundStyle(.blue)
                    Text(topic.detail)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .padding(.bottom, 2)
            }
        }

        // Blockers
        let blockers = summary.effectiveBlockers
        if !blockers.isEmpty {
            sectionHeader("Blockers")
            ForEach(blockers, id: \.self) { blocker in
                bulletPoint(blocker)
            }
        }

        // Next Steps
        let steps = summary.effectiveNextSteps
        if !steps.isEmpty {
            sectionHeader("Next Steps")
            ForEach(steps, id: \.self) { step in
                bulletPoint(step)
            }
        }

        // Speaker Contributions
        if let attributions = summary.speakerAttributions, !attributions.isEmpty {
            sectionHeader("Speaker Contributions")
            ForEach(attributions.keys.sorted(), id: \.self) { name in
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                    if let contributions = attributions[name] {
                        ForEach(contributions, id: \.self) { contribution in
                            bulletPoint(contribution)
                        }
                    }
                }
            }
        }

        // Open Questions (old format)
        let questions = summary.effectiveOpenQuestions
        if !questions.isEmpty && !summary.isNewFormat {
            sectionHeader("Open Questions")
            ForEach(questions, id: \.self) { q in
                bulletPoint(q)
            }
        }

        // Key Points (old format only)
        if !summary.isNewFormat, let keyPoints = summary.keyPoints, !keyPoints.isEmpty {
            sectionHeader("Key Points")
            ForEach(keyPoints, id: \.self) { point in
                bulletPoint(point)
            }
        }

        Text("Summarized by \(summary.modelUsed)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func summaryParagraphs(_ text: String) -> some View {
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if paragraphs.count > 1 {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        } else {
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
            .padding(.top, 4)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }

    private func emptyPanel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 40)
    }
}
