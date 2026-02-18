import Foundation
import MLXLLM
import MLXLMCommon

struct MLXModel: Identifiable {
    let id: String           // HuggingFace model ID e.g. "mlx-community/Llama-3.2-3B-Instruct-4bit"
    let displayName: String  // e.g. "Llama 3.2 3B"
    let description: String  // e.g. "Good balance of speed and quality"
    let sizeLabel: String    // e.g. "~2 GB"
    let ramRequired: String  // e.g. "~4 GB RAM"
    var isDownloaded: Bool = false
}

@MainActor
final class MLXModelManager: ObservableObject {
    @Published var models: [MLXModel] = []
    @Published var selectedModelId: String?
    @Published var downloadingModelId: String?
    @Published var downloadProgress: Double = 0

    private static let selectedModelKey = "selectedMLXModel"

    init() {
        selectedModelId = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        models = Self.knownModels()
        Task { await refreshDownloadStatus() }
    }

    var selectedModel: MLXModel? {
        guard let id = selectedModelId else { return nil }
        return models.first { $0.id == id }
    }

    var hasDownloadedModel: Bool {
        models.contains { $0.isDownloaded }
    }

    func selectModel(_ id: String) {
        selectedModelId = id
        UserDefaults.standard.set(id, forKey: Self.selectedModelKey)
    }

    func markModelDownloaded(_ id: String) {
        if let idx = models.firstIndex(where: { $0.id == id }) {
            models[idx].isDownloaded = true
        }
        if selectedModelId == nil {
            selectModel(id)
        }
    }

    func modelIsDownloaded(_ id: String) -> Bool {
        models.first { $0.id == id }?.isDownloaded ?? false
    }

    /// Download a model in a detached task so the HuggingFace Hub byte-by-byte
    /// iteration runs on the cooperative thread pool, NOT on the main thread
    /// where it would flood the autorelease pool.
    nonisolated func downloadModelDetached(
        _ id: String,
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Bool) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            do {
                let config = ModelConfiguration(id: id)
                _ = try await LLMModelFactory.shared.loadContainer(
                    configuration: config,
                    progressHandler: { progress in
                        onProgress(progress.fractionCompleted)
                    }
                )
                onComplete(true)
            } catch {
                onComplete(false)
            }
        }
    }

    func refreshDownloadStatus() async {
        let hub = defaultHubApi
        for i in models.indices {
            let config = ModelConfiguration(id: models[i].id)
            let modelDir = config.modelDirectory(hub: hub)
            // Check for config.json as a signal that the model is fully downloaded
            let configFile = modelDir.appending(path: "config.json")
            models[i].isDownloaded = FileManager.default.fileExists(atPath: configFile.path)
        }
        // If a model was previously selected, trust it
        if let selected = selectedModelId,
           let idx = models.firstIndex(where: { $0.id == selected }) {
            models[idx].isDownloaded = true
        }
    }

    private static func knownModels() -> [MLXModel] {
        [
            MLXModel(
                id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                displayName: "Llama 3.2 3B",
                description: "Good balance of speed and quality.",
                sizeLabel: "~2 GB",
                ramRequired: "~4 GB RAM"
            ),
            MLXModel(
                id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                displayName: "Qwen 2.5 7B",
                description: "High quality, needs more RAM.",
                sizeLabel: "~4 GB",
                ramRequired: "~8 GB RAM"
            ),
            MLXModel(
                id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
                displayName: "Mistral 7B v0.3",
                description: "Strong general-purpose model.",
                sizeLabel: "~4 GB",
                ramRequired: "~8 GB RAM"
            ),
        ]
    }
}
