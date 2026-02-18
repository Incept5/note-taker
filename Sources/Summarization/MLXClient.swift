import Foundation
import MLXLLM
import MLXLMCommon

@MainActor
final class MLXClient {
    private var container: ModelContainer?
    private var loadedModelId: String?

    var isModelLoaded: Bool { container != nil }

    /// Load (or reuse) a model. Downloads from HuggingFace Hub if not cached.
    /// Runs the heavy work in a detached task to keep the main thread free.
    nonisolated func loadModelDetached(
        id: String,
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<ModelContainer, Error>) -> Void
    ) {
        Task.detached(priority: .userInitiated) {
            do {
                let config = ModelConfiguration(id: id)
                let container = try await LLMModelFactory.shared.loadContainer(
                    configuration: config,
                    progressHandler: { progress in
                        onProgress(progress.fractionCompleted)
                    }
                )
                onComplete(.success(container))
            } catch {
                onComplete(.failure(error))
            }
        }
    }

    /// Ensure the model is loaded, reusing the existing container if the same model.
    func ensureModelLoaded(id: String) async throws {
        if loadedModelId == id, container != nil {
            return
        }
        // Unload any previous model
        unloadModel()

        let config = ModelConfiguration(id: id)
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: config
        )
        loadedModelId = id
    }

    /// Send a chat completion request using system prompt + user message.
    func chat(systemPrompt: String, userMessage: String) async throws -> String {
        guard let container else {
            throw SummarizationError.mlxModelNotDownloaded
        }

        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user(userMessage),
        ])

        let input = try await container.prepare(input: userInput)

        let parameters = GenerateParameters(
            maxTokens: 4000,
            temperature: 0.6,
            repetitionPenalty: 1.1,
            repetitionContextSize: 64
        )

        var output = ""
        let stream = try await container.generate(input: input, parameters: parameters)
        for await generation in stream {
            switch generation {
            case .chunk(let text):
                output += text
            case .info:
                break
            case .toolCall:
                break
            }
        }

        return output
    }

    func unloadModel() {
        container = nil
        loadedModelId = nil
    }
}
