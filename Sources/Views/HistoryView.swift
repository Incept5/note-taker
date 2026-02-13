import SwiftUI

struct HistoryView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: { appState.navigation = .none }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                Spacer()

                Text("History")
                    .font(.headline)

                Spacer()
                // Invisible spacer to balance the back button
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if appState.meetingStore.recentMeetings.isEmpty {
                emptyState
            } else {
                meetingList
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
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var meetingList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(appState.meetingStore.recentMeetings) { meeting in
                    Button(action: {
                        appState.navigation = .meetingDetail(meeting)
                    }) {
                        MeetingRow(meeting: meeting)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            try? appState.meetingStore.deleteMeeting(id: meeting.id)
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
