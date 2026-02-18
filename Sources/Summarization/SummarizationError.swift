import Foundation

enum SummarizationError: LocalizedError {
    case ollamaNotRunning
    case noModelsAvailable
    case noModelSelected
    case requestFailed(Error)
    case invalidResponse
    case mlxModelNotDownloaded
    case mlxModelNotSelected
    case mlxLoadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .ollamaNotRunning:
            return "Ollama is not running. Start it with 'ollama serve' in Terminal."
        case .noModelsAvailable:
            return "No models available in Ollama. Pull one with 'ollama pull llama3.2'."
        case .noModelSelected:
            return "No summarization model selected."
        case .requestFailed(let error):
            return "Summarization request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from Ollama."
        case .mlxModelNotDownloaded:
            return "Download a summarization model in Settings."
        case .mlxModelNotSelected:
            return "Select a summarization model in Settings."
        case .mlxLoadFailed(let error):
            return "Failed to load the MLX model: \(error.localizedDescription)"
        }
    }
}
