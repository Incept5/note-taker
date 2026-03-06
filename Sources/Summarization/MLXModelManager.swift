import Foundation
import MLXLLM
import MLXLMCommon

struct MLXModel: Identifiable, Codable {
    let id: String           // HuggingFace model ID e.g. "mlx-community/Llama-3.2-3B-Instruct-4bit"
    let displayName: String  // e.g. "Llama 3.2 3B"
    let description: String  // e.g. "Good balance of speed and quality"
    let sizeLabel: String    // e.g. "~2 GB"
    let ramRequired: String  // e.g. "~4 GB RAM"
    var isDownloaded: Bool = false
    var isCustom: Bool = false
}

@MainActor
final class MLXModelManager: ObservableObject {
    @Published var models: [MLXModel] = []
    @Published var selectedModelId: String?
    @Published var downloadingModelId: String?
    @Published var downloadProgress: Double = 0

    private static let selectedModelKey = "selectedMLXModel"
    private static let customModelsKey = "customMLXModels"
    private static let removedModelIdsKey = "removedMLXModelIds"

    init() {
        selectedModelId = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        let removedIds = Self.loadRemovedIds()
        let curated = Self.knownModels().filter { !removedIds.contains($0.id) }
        let custom = Self.loadCustomModels()
        models = curated + custom
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

    // MARK: - Custom Model Management

    @discardableResult
    func addCustomModel(id: String) -> String? {
        var trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)

        // Accept full HuggingFace URLs — extract org/model from the path
        if trimmed.contains("huggingface.co/") {
            let parts = trimmed.components(separatedBy: "huggingface.co/")
            if let path = parts.last {
                let segments = path.split(separator: "/").map(String.init)
                if segments.count >= 2 {
                    trimmed = "\(segments[0])/\(segments[1])"
                }
            }
        }

        guard !trimmed.isEmpty else { return nil }
        guard !models.contains(where: { $0.id == trimmed }) else { return nil }

        // Derive display name from HuggingFace ID (strip org prefix)
        let displayName = trimmed.contains("/")
            ? String(trimmed.split(separator: "/").last ?? Substring(trimmed))
            : trimmed

        let model = MLXModel(
            id: trimmed,
            displayName: displayName,
            description: "Custom model",
            sizeLabel: "Unknown",
            ramRequired: "Unknown",
            isCustom: true
        )
        models.append(model)

        var custom = Self.loadCustomModels()
        custom.append(model)
        Self.saveCustomModels(custom)

        // Also remove from removed IDs in case user is re-adding a previously removed curated model
        var removedIds = Self.loadRemovedIds()
        if removedIds.remove(trimmed) != nil {
            Self.saveRemovedIds(removedIds)
        }

        Task { await refreshDownloadStatus() }
        return trimmed
    }

    func removeModel(_ id: String) {
        guard let idx = models.firstIndex(where: { $0.id == id }) else { return }
        let model = models[idx]

        if model.isCustom {
            var custom = Self.loadCustomModels()
            custom.removeAll { $0.id == id }
            Self.saveCustomModels(custom)
        } else {
            var removedIds = Self.loadRemovedIds()
            removedIds.insert(id)
            Self.saveRemovedIds(removedIds)
        }

        models.remove(at: idx)

        if selectedModelId == id {
            selectedModelId = nil
            UserDefaults.standard.removeObject(forKey: Self.selectedModelKey)
        }
    }

    // MARK: - Persistence

    private static func loadCustomModels() -> [MLXModel] {
        guard let data = UserDefaults.standard.data(forKey: customModelsKey),
              let decoded = try? JSONDecoder().decode([MLXModel].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveCustomModels(_ models: [MLXModel]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: customModelsKey)
        }
    }

    private static func loadRemovedIds() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: removedModelIdsKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(decoded)
    }

    private static func saveRemovedIds(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(Array(ids)) {
            UserDefaults.standard.set(data, forKey: removedModelIdsKey)
        }
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
        // If selected model isn't actually downloaded, clear the selection
        if let selected = selectedModelId,
           let idx = models.firstIndex(where: { $0.id == selected }),
           !models[idx].isDownloaded {
            selectedModelId = nil
            UserDefaults.standard.removeObject(forKey: Self.selectedModelKey)
        }
    }

    private static func knownModels() -> [MLXModel] {
        [
            MLXModel(
                id: "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit",
                displayName: "Qwen3 30B MoE",
                description: "Best quality — 30B MoE, only 3B active. Needs 32GB RAM.",
                sizeLabel: "~17 GB",
                ramRequired: "~20 GB RAM"
            ),
            MLXModel(
                id: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                displayName: "Qwen3 4B",
                description: "Fast and capable, great for 16GB machines.",
                sizeLabel: "~2.3 GB",
                ramRequired: "~4 GB RAM"
            ),
            MLXModel(
                id: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
                displayName: "Llama 3.1 8B",
                description: "Strong general-purpose summarization.",
                sizeLabel: "~4 GB",
                ramRequired: "~8 GB RAM"
            ),
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
            MLXModel(
                id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
                displayName: "Qwen 2.5 3B",
                description: "Fast and capable, low RAM usage.",
                sizeLabel: "~2 GB",
                ramRequired: "~4 GB RAM"
            ),
        ]
    }
}
