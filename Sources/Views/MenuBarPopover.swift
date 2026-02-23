import SwiftUI

struct MenuBarPopover: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Group {
            if appState.showingOnboarding {
                OnboardingView(appState: appState)
                    .frame(width: 320)
            } else {
                VStack(spacing: 0) {
                    mainContent
                }
                .frame(width: 320)
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("NoteTaker")
                    .font(.headline)
                Spacer()

                Button(action: { appState.onOpenHistory?() }) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Meeting History")

                Button(action: { appState.onOpenSettings?() }) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit NoteTaker")
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Content based on phase
            switch appState.phase {
            case .idle:
                ReadyView(appState: appState)

            case .recording(let since, let transcript):
                RecordingView(appState: appState, startedAt: since, transcript: transcript)

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

    private func stoppedView(_ audio: CapturedAudio) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Recording Complete")
                .font(.headline)

            Text("Duration: \(audio.formattedDuration)")
                .foregroundStyle(.secondary)

            Button("Transcribe") {
                appState.startTranscription(audio: audio)
            }
            .buttonStyle(.borderedProminent)

            Button("New Recording") {
                appState.reset()
            }
            .padding(.bottom, 12)
        }
        .padding()
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
