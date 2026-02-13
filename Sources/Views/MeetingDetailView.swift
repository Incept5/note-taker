import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var appState: AppState
    let meeting: MeetingRecord

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

                if meeting.summaryJSON != nil || meeting.combinedTranscript != nil {
                    Button(action: {
                        let summary = meeting.decodedSummary()
                        let transcript = meeting.combinedTranscript ?? ""
                        let duration = meeting.formattedDuration
                        if let summary {
                            appState.onShowResultWindow?(summary, transcript, duration)
                        }
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Window")
                }

                Menu {
                    Button("Copy Summary") {
                        if let summary = meeting.decodedSummary() {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(summary.markdownText, forType: .string)
                        }
                    }
                    .disabled(meeting.summaryJSON == nil)

                    Button("Copy Transcript") {
                        if let text = meeting.combinedTranscript {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                    .disabled(meeting.combinedTranscript == nil)

                    Divider()

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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Meeting info header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.appName ?? "Unknown App")
                            .font(.headline)
                        HStack {
                            Text(meeting.formattedDate)
                            Text("·")
                            Text(meeting.formattedDuration)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    // Summary section
                    if let summary = meeting.decodedSummary() {
                        summarySection(summary)
                    }

                    // Transcript section
                    if let transcript = meeting.combinedTranscript, !transcript.isEmpty {
                        transcriptSection(transcript)
                    }

                    if meeting.combinedTranscript == nil && meeting.summaryJSON == nil {
                        Text("No transcript or summary available for this meeting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private func summarySection(_ summary: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Summary")
            Text(summary.summary)
                .font(.callout)

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

            Text("Summarized by \(summary.modelUsed)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func transcriptSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Transcript")
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }

}
