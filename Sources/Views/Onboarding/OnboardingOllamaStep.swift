import SwiftUI

struct OnboardingOllamaStep: View {
    @ObservedObject var appState: AppState
    let onContinue: () -> Void

    @State private var ollamaAvailable = false
    @State private var ollamaModels: [OllamaModel] = []
    @State private var checking = true

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            HStack(spacing: 6) {
                Text("AI Summarization")
                    .font(.headline)
                Text("Optional")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary, in: Capsule())
            }

            Text("Ollama runs a local LLM to generate meeting summaries. Transcription works without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if checking {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking Ollama...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if ollamaAvailable {
                Label("Ollama is running", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.bold())

                if ollamaModels.isEmpty {
                    VStack(spacing: 6) {
                        Text("No models installed yet. Run:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("ollama pull llama3.2")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                        Button("Check Again") {
                            Task { await checkOllama() }
                        }
                        .controlSize(.small)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ollamaModels, id: \.name) { model in
                            HStack {
                                Text(model.name)
                                    .font(.caption)
                                Spacer()
                                if appState.selectedOllamaModel == model.name {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)
                }
            } else {
                VStack(spacing: 10) {
                    Text("Ollama is not running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Install from ollama.com, then run:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("ollama pull llama3.2")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    HStack(spacing: 12) {
                        Button("Open ollama.com") {
                            NSWorkspace.shared.open(URL(string: "https://ollama.com")!)
                        }
                        .controlSize(.small)

                        Button("Check Again") {
                            Task { await checkOllama() }
                        }
                        .controlSize(.small)
                    }
                }
            }

            Spacer()

            HStack(spacing: 12) {
                if !ollamaAvailable || ollamaModels.isEmpty {
                    Button("Skip for Now") {
                        onContinue()
                    }
                    .controlSize(.large)
                }

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 16)
        }
        .padding()
        .task {
            await checkOllama()
        }
    }

    private func checkOllama() async {
        checking = true
        let client = OllamaClient()
        ollamaAvailable = await client.checkAvailability()
        if ollamaAvailable {
            ollamaModels = (try? await client.listModels()) ?? []
            // Auto-select first model if none selected
            if appState.selectedOllamaModel == nil, let first = ollamaModels.first {
                appState.selectedOllamaModel = first.name
            }
        }
        checking = false
    }
}
