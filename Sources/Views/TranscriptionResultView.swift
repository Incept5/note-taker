import SwiftUI

struct TranscriptionResultView: View {
    @ObservedObject var appState: AppState
    let audio: CapturedAudio
    let result: MeetingTranscription
    let onNewRecording: () -> Void

    @State private var ollamaAvailable = false
    @State private var ollamaModels: [OllamaModel] = []
    @State private var checkingOllama = true

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.document.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)

            Text("Transcription Complete")
                .font(.headline)

            HStack(spacing: 16) {
                Label(audio.formattedDuration, systemImage: "clock")
                Label(result.modelUsed, systemImage: "cpu")
                Label(formatProcessingTime(result.processingDuration), systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let mic = result.micTranscript, !mic.fullText.isEmpty {
                        sectionHeader("Others")
                        Text(result.systemTranscript.fullText)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)

                        sectionHeader("You")
                        Text(mic.fullText)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                    } else {
                        Text(result.systemTranscript.fullText)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)

            Divider()

            // Ollama summarization section
            ollamaSection

            Divider()

            HStack(spacing: 12) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.combinedText, forType: .string)
                }

                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: audio.directory.path)
                }

                Button("New Recording") {
                    onNewRecording()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 12)
        }
        .padding()
        .task {
            await checkOllama()
        }
    }

    @ViewBuilder
    private var ollamaSection: some View {
        if checkingOllama {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Ollama...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if ollamaAvailable {
            VStack(spacing: 8) {
                if ollamaModels.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No models installed in Ollama.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Run: ollama pull llama3.2")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                } else {
                    HStack {
                        Picker("Model", selection: Binding(
                            get: { appState.selectedOllamaModel ?? "" },
                            set: { appState.selectedOllamaModel = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Select model...").tag("")
                            ForEach(ollamaModels, id: \.name) { model in
                                Text("\(model.name) (\(model.parameterSize))")
                                    .tag(model.name)
                            }
                        }
                        .labelsHidden()

                        Button("Summarize") {
                            appState.startSummarization(audio: audio, transcription: result)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(appState.selectedOllamaModel == nil)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("Ollama not running", systemImage: "exclamationmark.triangle")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Text("Install Ollama from ollama.ai, then run:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("ollama pull llama3.2")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                Button("Retry") {
                    checkingOllama = true
                    Task { await checkOllama() }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    private func checkOllama() async {
        let client = OllamaClient()
        ollamaAvailable = await client.checkAvailability()
        if ollamaAvailable {
            ollamaModels = (try? await client.listModels()) ?? []
            // Auto-select first model if none selected
            if appState.selectedOllamaModel == nil, let first = ollamaModels.first {
                appState.selectedOllamaModel = first.name
            }
        }
        checkingOllama = false
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func formatProcessingTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }
}
