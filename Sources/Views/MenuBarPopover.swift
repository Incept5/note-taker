import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("NoteTaker")
                    .font(.headline)
                Spacer()
                Text("Phase 1 PoC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Content based on phase
            switch appState.phase {
            case .idle:
                AppPickerView(appState: appState)

            case .recording(let since):
                RecordingView(appState: appState, startedAt: since)

            case .stopped(let audio):
                stoppedView(audio)

            case .error(let message):
                errorView(message)
            }
        }
        .frame(width: 320)
    }

    private func stoppedView(_ audio: CapturedAudio) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Recording Complete")
                .font(.headline)

            Text("Duration: \(audio.formattedDuration)")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                fileRow("System Audio", url: audio.systemAudioURL)
                fileRow("Microphone", url: audio.microphoneURL)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: audio.directory.path)
                }

                Button("New Recording") {
                    appState.reset()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 12)
        }
        .padding()
    }

    private func fileRow(_ label: String, url: URL) -> some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(label)
                    .font(.caption.bold())
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow)

            Text("Error")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if message.contains("Screen Recording") || message.contains("tap creation") {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }

            Button("Try Again") {
                appState.reset()
            }
            .padding(.bottom, 12)
        }
        .padding()
    }
}
