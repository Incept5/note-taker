import SwiftUI

struct AppPickerView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.discovery.processes.isEmpty {
                emptyState
            } else {
                processList
            }

            Divider()

            // Start button
            HStack {
                Button(action: { appState.discovery.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh process list")

                Spacer()

                Button("Start Recording") {
                    appState.startRecording()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.selectedProcess == nil)
            }
            .padding(12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No audio sources found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Play audio in an app to see it here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var processList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(appState.discovery.processes) { process in
                    ProcessRow(
                        process: process,
                        isSelected: appState.selectedProcess?.id == process.id
                    )
                    .onTapGesture {
                        appState.selectedProcess = process
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 200, maxHeight: 300)
    }
}

// MARK: - ProcessRow

private struct ProcessRow: View {
    let process: AudioProcess
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // App icon
            Image(nsImage: process.icon)
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(process.name)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)

                    if process.isMeetingApp {
                        Image(systemName: "video.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }

                if let bundleID = process.bundleID {
                    Text(bundleID)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Audio active indicator
            Circle()
                .fill(process.audioActive ? .green : .gray.opacity(0.3))
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 4)
    }
}
