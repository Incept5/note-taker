import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var appState: AppState
    @ObservedObject var audioDeviceManager: AudioDeviceManager
    let onDismiss: () -> Void
    var onModelReady: (() -> Void)? = nil

    @State private var ollamaModels: [OllamaModel] = []
    @State private var ollamaAvailable = false
    @State private var checkingOllama = true
    @State private var editingURL: String = ""
    @State private var downloadingId: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                audioInputSection
                Divider()
                ollamaSection
                Divider()
                whisperSection
            }
            .padding(20)
        }
        .task {
            editingURL = appState.ollamaServerURL
            await loadOllamaModels()
        }
    }

    // MARK: - Audio Input Section

    @ViewBuilder
    private var audioInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Microphone Input", systemImage: "mic")
                .font(.title3.bold())

            let devices = audioDeviceManager.inputDevices
            let selectedUID = audioDeviceManager.selectedInputDeviceUID

            if devices.isEmpty {
                Label("No input devices found", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                // System Default option
                audioDeviceRow(
                    name: "System Default",
                    detail: devices.first(where: { $0.isDefault })?.name,
                    isSelected: selectedUID == nil
                ) {
                    audioDeviceManager.selectedInputDeviceUID = nil
                }

                // Individual devices
                ForEach(devices) { device in
                    audioDeviceRow(
                        name: device.name,
                        detail: device.isDefault ? "Default" : nil,
                        isSelected: selectedUID == device.uid
                    ) {
                        audioDeviceManager.selectedInputDeviceUID = device.uid
                    }
                }
            }

            // If selected device is disconnected, show warning
            if let selected = selectedUID,
               !devices.contains(where: { $0.uid == selected }) {
                Label("Selected device disconnected — will use system default", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func audioDeviceRow(name: String, detail: String?, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.body.bold())
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Text("Active")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Select") { onSelect() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            isSelected ? Color.blue.opacity(0.08) : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Ollama Section

    @ViewBuilder
    private var ollamaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Summarization (Ollama)", systemImage: "brain")
                .font(.title3.bold())

            // Server URL
            serverURLField

            // Model list
            if checkingOllama {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking Ollama at \(appState.ollamaServerURL)...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if !ollamaAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Cannot connect to Ollama", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.bold())
                        .foregroundStyle(.orange)

                    Text("Make sure Ollama is running at the URL above.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if appState.ollamaServerURL == OllamaClient.defaultBaseURL {
                        Text("Install from ollama.ai, then run:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("ollama pull llama3.2")
                            .font(.callout.monospaced())
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Button("Retry Connection") {
                        checkingOllama = true
                        Task { await loadOllamaModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if ollamaModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Connected — no models installed", systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.green)
                    Text("Run: ollama pull llama3.2")
                        .font(.callout.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    Button("Refresh Models") {
                        Task { await loadOllamaModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Refresh") {
                            Task { await loadOllamaModels() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }

                    ForEach(ollamaModels, id: \.name) { model in
                        ollamaModelRow(model)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func ollamaModelRow(_ model: OllamaModel) -> some View {
        let isSelected = appState.selectedOllamaModel == model.name
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
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
                Text("Selected")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Select") {
                    appState.selectedOllamaModel = model.name
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            isSelected ? Color.purple.opacity(0.08) : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Server URL

    @ViewBuilder
    private var serverURLField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server URL")
                .font(.callout.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("http://localhost:11434", text: $editingURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit { applyServerURL() }

                if editingURL != appState.ollamaServerURL {
                    Button("Connect") { applyServerURL() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                if appState.ollamaServerURL != OllamaClient.defaultBaseURL {
                    Button("Reset") {
                        editingURL = OllamaClient.defaultBaseURL
                        applyServerURL()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if appState.ollamaServerURL != OllamaClient.defaultBaseURL {
                Label("Using remote server", systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.purple)
            } else {
                Text("Default: localhost. Change this to use a remote Ollama instance.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func applyServerURL() {
        let url = editingURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        appState.ollamaServerURL = url
        checkingOllama = true
        ollamaModels = []
        Task { await loadOllamaModels() }
    }

    // MARK: - WhisperKit Section

    private var whisperSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcription (WhisperKit)", systemImage: "waveform")
                .font(.title3.bold())

            ForEach(modelManager.models) { model in
                whisperModelRow(model)
            }

            if let error = downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func whisperModelRow(_ model: WhisperModel) -> some View {
        let isSelected = model.id == modelManager.selectedModelName
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.body.bold())
                    if isSelected {
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
                if isSelected {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Select") {
                        modelManager.selectModel(model.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if downloadingId == model.id {
                VStack(spacing: 2) {
                    ProgressView(value: downloadProgress)
                        .frame(width: 80)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
                    startDownload(model.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(downloadingId != nil)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Download

    private func startDownload(_ modelId: String) {
        downloadError = nil
        downloadingId = modelId
        downloadProgress = 0
        modelManager.downloadModelDetached(
            modelId,
            onProgress: { fraction in
                DispatchQueue.main.async {
                    downloadProgress = fraction
                }
            },
            onComplete: { success in
                DispatchQueue.main.async {
                    // Clear local @State first
                    downloadingId = nil
                    if !success {
                        downloadError = "Download failed. Please try again."
                    }
                    // Defer @Published update to next runloop cycle so
                    // the @State re-render completes first.
                    if success {
                        DispatchQueue.main.async {
                            modelManager.markModelDownloaded(modelId)
                        }
                    }
                }
            }
        )
    }

    // MARK: - Helpers

    private func loadOllamaModels() async {
        let client = OllamaClient(baseURL: appState.ollamaServerURL)
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
