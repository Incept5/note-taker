import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var appState: AppState
    @ObservedObject var mlxModelManager: MLXModelManager
    let onDismiss: () -> Void
    var onModelReady: (() -> Void)? = nil

    @State private var ollamaModels: [OllamaModel] = []
    @State private var ollamaAvailable = false
    @State private var checkingOllama = true
    @State private var editingURL: String = ""
    @State private var downloadingId: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?

    // MLX download state (local @State to avoid layout recursion)
    @State private var mlxDownloadingId: String?
    @State private var mlxDownloadProgress: Double = 0
    @State private var mlxDownloadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                audioSection
                Divider()
                GoogleCalendarSettingsSection(appState: appState)
                Divider()
                summarizationSection
                Divider()
                whisperSection
            }
            .padding(20)
        }
        .task {
            editingURL = appState.ollamaServerURL
            if appState.summarizationBackend == "ollama" {
                await loadOllamaModels()
            }
        }
    }

    // MARK: - Audio Section

    @ViewBuilder
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio Capture", systemImage: "waveform.circle")
                .font(.title3.bold())

            Toggle(isOn: $appState.micEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include microphone")
                        .font(.body)
                    Text("Mix your mic input into the recording so your voice appears in the transcript.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            if appState.micEnabled {
                micDevicePicker
            }

            Divider()

            Toggle(isOn: $appState.autoRecordEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-record when meeting starts")
                        .font(.body)
                    Text("Automatically starts recording when Zoom or Teams launches, and stops when the app quits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Recording retention")
                    .font(.body)

                Picker("Keep recordings for", selection: $appState.recordingRetentionDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("28 days").tag(28)
                    Text("60 days").tag(60)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)

                Text("Audio files older than this are deleted on launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var micDevicePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Microphone")
                .font(.callout.bold())
                .foregroundStyle(.secondary)

            if appState.audioDeviceManager.inputDevices.isEmpty {
                Text("No input devices found")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                ForEach(appState.audioDeviceManager.inputDevices) { device in
                    micDeviceRow(device)
                }
            }
        }
    }

    @ViewBuilder
    private func micDeviceRow(_ device: AudioInputDevice) -> some View {
        let selectedUID = appState.audioDeviceManager.selectedInputDeviceUID
        let isSelected = device.uid == selectedUID || (selectedUID == nil && device.isDefault)

        HStack(spacing: 8) {
            Image(systemName: isSelected ? "mic.circle.fill" : "mic.circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.body)
                if device.isDefault {
                    Text("System Default")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .font(.caption.bold())
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // nil means "use system default"
            appState.audioDeviceManager.selectedInputDeviceUID =
                device.isDefault ? nil : device.uid
        }
    }

    // MARK: - Summarization Section

    @ViewBuilder
    private var summarizationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Summarization", systemImage: "brain")
                .font(.title3.bold())

            Picker("Engine", selection: $appState.summarizationBackend) {
                Text("Built-in (MLX)").tag("mlx")
                Text("Ollama").tag("ollama")
            }
            .pickerStyle(.segmented)

            if appState.summarizationBackend == "mlx" {
                mlxModelSection
            } else {
                ollamaModelSection
            }
        }
    }

    // MARK: - MLX Model Section

    @ViewBuilder
    private var mlxModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mlxModelManager.models) { model in
                mlxModelRow(model)
            }

            if let error = mlxDownloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func mlxModelRow(_ model: MLXModel) -> some View {
        let isSelected = appState.selectedMLXModel == model.id
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
                Text("\(model.sizeLabel) · \(model.ramRequired)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if model.isDownloaded {
                if isSelected {
                    Text("Selected")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Select") {
                        appState.selectedMLXModel = model.id
                        mlxModelManager.selectModel(model.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if mlxDownloadingId == model.id {
                VStack(spacing: 2) {
                    ProgressView(value: mlxDownloadProgress)
                        .frame(width: 80)
                    Text("\(Int(mlxDownloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
                    startMLXDownload(model.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(mlxDownloadingId != nil)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            isSelected ? Color.purple.opacity(0.08) : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }

    // MARK: - Ollama Model Section

    @ViewBuilder
    private var ollamaModelSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                .task { await loadOllamaModels() }
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

    // MARK: - WhisperKit Download

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

    // MARK: - MLX Download

    private func startMLXDownload(_ modelId: String) {
        mlxDownloadError = nil
        mlxDownloadingId = modelId
        mlxDownloadProgress = 0
        mlxModelManager.downloadModelDetached(
            modelId,
            onProgress: { fraction in
                DispatchQueue.main.async {
                    mlxDownloadProgress = fraction
                }
            },
            onComplete: { success in
                DispatchQueue.main.async {
                    mlxDownloadingId = nil
                    if !success {
                        mlxDownloadError = "Download failed. Please try again."
                    }
                    // Defer @Published update to next runloop cycle
                    if success {
                        DispatchQueue.main.async {
                            mlxModelManager.markModelDownloaded(modelId)
                            appState.selectedMLXModel = modelId
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
