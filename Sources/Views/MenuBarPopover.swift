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
                Button(action: { appState.showingModelPicker.toggle() }) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Model Settings")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Model picker sheet
            if appState.showingModelPicker {
                ModelPickerView(
                    modelManager: appState.modelManager,
                    onDismiss: { appState.showingModelPicker = false }
                )
            } else {
                // Content based on phase
                switch appState.phase {
                case .idle:
                    AppPickerView(appState: appState)

                case .recording(let since):
                    RecordingView(appState: appState, startedAt: since)

                case .stopped(let audio):
                    stoppedView(audio)

                case .transcribing(_, let progress):
                    TranscribingView(
                        transcriptionService: appState.transcriptionService,
                        progress: progress
                    )

                case .transcribed(let audio, let result):
                    TranscriptionResultView(
                        appState: appState,
                        audio: audio,
                        result: result,
                        onNewRecording: { appState.reset() }
                    )

                case .summarizing:
                    SummarizingView(
                        summarizationService: appState.summarizationService
                    )

                case .summarized(let audio, let transcription, let summary):
                    SummaryResultView(
                        summary: summary,
                        audio: audio,
                        transcription: transcription,
                        onViewTranscript: {
                            appState.phase = .transcribed(audio, transcription)
                        },
                        onRegenerate: {
                            appState.startSummarization(audio: audio, transcription: transcription)
                        },
                        onNewRecording: { appState.reset() }
                    )

                case .error(let message):
                    errorView(message)
                }
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

            let hasModel = appState.modelManager.hasDownloadedModel
            if hasModel {
                Button("Transcribe") {
                    appState.startTranscription(audio: audio)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Download Model to Transcribe") {
                    appState.showingModelPicker = true
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 12) {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: audio.directory.path)
                }

                Button("New Recording") {
                    appState.reset()
                }
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
