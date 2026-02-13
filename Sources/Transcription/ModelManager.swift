import Foundation
import WhisperKit

struct WhisperModel: Identifiable {
    let id: String // variant name used by WhisperKit
    let displayName: String
    let description: String
    let sizeLabel: String

    var isDownloaded: Bool = false
}

@MainActor
final class ModelManager: ObservableObject {
    @Published var models: [WhisperModel] = []
    @Published var selectedModelName: String?
    @Published var downloadingModelId: String?
    @Published var downloadProgress: Double = 0

    private static let selectedModelKey = "selectedWhisperModel"
    private static let modelRepo = "argmaxinc/whisperkit-coreml"

    init() {
        selectedModelName = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        models = Self.knownModels()
        Task { await refreshDownloadStatus() }
    }

    var selectedModel: WhisperModel? {
        guard let name = selectedModelName else { return nil }
        return models.first { $0.id == name }
    }

    var hasDownloadedModel: Bool {
        models.contains { $0.isDownloaded }
    }

    func selectModel(_ id: String) {
        selectedModelName = id
        UserDefaults.standard.set(id, forKey: Self.selectedModelKey)
    }

    func downloadModel(_ id: String) async throws {
        guard !models.contains(where: { $0.id == id && $0.isDownloaded }) else { return }

        downloadingModelId = id
        downloadProgress = 0

        do {
            _ = try await WhisperKit.download(
                variant: id,
                from: Self.modelRepo,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress.fractionCompleted
                    }
                }
            )

            if let idx = models.firstIndex(where: { $0.id == id }) {
                models[idx].isDownloaded = true
            }

            // Auto-select if no model selected yet
            if selectedModelName == nil {
                selectModel(id)
            }

            downloadingModelId = nil
            downloadProgress = 1.0
        } catch {
            downloadingModelId = nil
            downloadProgress = 0
            throw error
        }
    }

    /// Returns the local folder path for a downloaded model, or nil if not found.
    func modelFolder(for variant: String) -> String? {
        let base = URL.homeDirectory
            .appending(path: "Library/Caches")
            .appending(path: "com.incept5.NoteTaker")
        let hubDefault = URL.homeDirectory
            .appending(path: ".cache/huggingface/hub")

        // WhisperKit stores downloaded models under the huggingface cache.
        // Try the HF hub cache layout: models--{repo}/snapshots/*/openai_{variant}
        let repoDir = hubDefault
            .appending(path: "models--argmaxinc--whisperkit-coreml")
            .appending(path: "snapshots")

        if let snapshots = try? FileManager.default.contentsOfDirectory(
            at: repoDir, includingPropertiesForKeys: nil
        ) {
            for snapshot in snapshots {
                let modelDir = snapshot.appending(path: "openai_whisper-\(variant)")
                if FileManager.default.fileExists(atPath: modelDir.path) {
                    return modelDir.path
                }
            }
            // Also check without openai_ prefix
            for snapshot in snapshots {
                let modelDir = snapshot.appending(path: variant)
                if FileManager.default.fileExists(atPath: modelDir.path) {
                    return modelDir.path
                }
            }
        }

        // Fallback: check app caches directory
        let appModelDir = base.appending(path: variant)
        if FileManager.default.fileExists(atPath: appModelDir.path) {
            return appModelDir.path
        }

        return nil
    }

    func refreshDownloadStatus() async {
        for i in models.indices {
            models[i].isDownloaded = modelFolder(for: models[i].id) != nil
        }
        // Validate selected model is still downloaded
        if let selected = selectedModelName,
           !models.contains(where: { $0.id == selected && $0.isDownloaded }) {
            selectedModelName = nil
            UserDefaults.standard.removeObject(forKey: Self.selectedModelKey)
        }
    }

    private static func knownModels() -> [WhisperModel] {
        [
            WhisperModel(
                id: "tiny",
                displayName: "Tiny",
                description: "Fastest, lowest accuracy. Good for testing.",
                sizeLabel: "~75 MB"
            ),
            WhisperModel(
                id: "base",
                displayName: "Base",
                description: "Fast with decent accuracy.",
                sizeLabel: "~140 MB"
            ),
            WhisperModel(
                id: "small",
                displayName: "Small",
                description: "Good balance of speed and accuracy.",
                sizeLabel: "~460 MB"
            ),
            WhisperModel(
                id: "large-v3",
                displayName: "Large v3",
                description: "Best accuracy. Requires more RAM.",
                sizeLabel: "~3 GB"
            ),
            WhisperModel(
                id: "large-v3-turbo",
                displayName: "Large v3 Turbo",
                description: "Near-best accuracy, faster than large-v3.",
                sizeLabel: "~1.5 GB"
            ),
        ]
    }
}
