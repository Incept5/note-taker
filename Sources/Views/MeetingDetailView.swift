import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var appState: AppState
    let meeting: MeetingRecord

    @State private var copiedSummary = false
    @State private var copiedTranscript = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { appState.navigation = .history }) {
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
                        appState.navigation = .history
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
                            NSPasteboard.general.setString(summary.markdownText, forType: .string)
                            copiedSummary = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                copiedSummary = false
                            }
                        }
                    }
                ) {
                    if let summary = meeting.decodedSummary() {
                        summaryContent(summary)
                    } else {
                        emptyState("No summary available")
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
                        emptyState("No transcript available")
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Panel

    private func panelView<Content: View>(
        title: String,
        copied: Binding<Bool>,
        hasContent: Bool,
        onCopy: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Panel header with copy button
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
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

    // MARK: - Summary Content

    @ViewBuilder
    private func summaryContent(_ summary: MeetingSummary) -> some View {
        if !summary.keyPoints.isEmpty {
            sectionHeader("Key Points")
            ForEach(summary.keyPoints, id: \.self) { point in
                bulletPoint(point)
            }
        }

        if !summary.decisions.isEmpty {
            sectionHeader("Decisions")
            ForEach(summary.decisions, id: \.self) { decision in
                bulletPoint(decision)
            }
        }

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

        if !summary.openQuestions.isEmpty {
            sectionHeader("Open Questions")
            ForEach(summary.openQuestions, id: \.self) { q in
                bulletPoint(q)
            }
        }

        sectionHeader("Full Summary")
        summaryParagraphs(summary.summary)

        Text("Summarized by \(summary.modelUsed)")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Transcript Content

    @ViewBuilder
    private func transcriptContent(_ transcription: MeetingTranscription) -> some View {
        SegmentedTranscriptView(speakerSegments: transcription.interleavedSpeakerSegments())
    }

    // MARK: - Helpers

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

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 40)
    }
}
