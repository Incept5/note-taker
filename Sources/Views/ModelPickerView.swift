import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var appState: AppState
    let onDismiss: () -> Void
    var onModelReady: (() -> Void)? = nil

    @State private var ollamaModels: [OllamaModel] = []
    @State private var ollamaAvailable = false
    @State private var checkingOllama = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Ollama summarization models
                    ollamaSection

                    Divider()

                    // WhisperKit transcription models
                    whisperSection
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 12)
        .task {
            await loadOllamaModels()
        }
    }

    // MARK: - Ollama Section

    @ViewBuilder
    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summarization Model")
                .font(.subheadline.bold())

            if checkingOllama {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking Ollama...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !ollamaAvailable {
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
                        Task { await loadOllamaModels() }
                    }
                    .controlSize(.small)
                }
            } else if ollamaModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ollama is running but no models are installed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Run: ollama pull llama3.2")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

                    Button("Refresh") {
                        Task { await loadOllamaModels() }
                    }
                    .controlSize(.small)
                }
            } else {
                ForEach(ollamaModels, id: \.name) { model in
                    ollamaModelRow(model)
                }
            }
        }
    }

    @ViewBuilder
    private func ollamaModelRow(_ model: OllamaModel) -> some View {
        let isSelected = appState.selectedOllamaModel == model.name
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.name)
                        .font(.body.bold())
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                if !model.parameterSize.isEmpty {
                    Text(model.parameterSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Select") {
                    appState.selectedOllamaModel = model.name
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.purple.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    // MARK: - WhisperKit Section

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcription Model")
                .font(.subheadline.bold())

            ForEach(modelManager.models) { model in
                whisperModelRow(model)
            }

            if modelManager.selectedModelName != nil {
                Text("Selected: \(modelManager.selectedModel?.displayName ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func whisperModelRow(_ model: WhisperModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.displayName)
                        .font(.body.bold())
                    if model.id == modelManager.selectedModelName {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.sizeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if model.isDownloaded {
                if model.id == modelManager.selectedModelName {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Select") {
                        modelManager.selectModel(model.id)
                        onModelReady?()
                    }
                    .controlSize(.small)
                }
            } else if modelManager.downloadingModelId == model.id {
                VStack(spacing: 2) {
                    ProgressView(value: modelManager.downloadProgress)
                        .frame(width: 60)
                    Text("\(Int(modelManager.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
                    Task {
                        do {
                            try await modelManager.downloadModel(model.id)
                            onModelReady?()
                        } catch {
                            // Error is visible via downloadProgress reset
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            model.id == modelManager.selectedModelName
                ? Color.accentColor.opacity(0.1)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    // MARK: - Helpers

    private func loadOllamaModels() async {
        let client = OllamaClient()
        ollamaAvailable = await client.checkAvailability()
        if ollamaAvailable {
            ollamaModels = (try? await client.listModels()) ?? []
            if appState.selectedOllamaModel == nil, let first = ollamaModels.first {
                appState.selectedOllamaModel = first.name
            }
        }
        checkingOllama = false
    }
}
