import Foundation

enum TranscriptionError: LocalizedError {
    case noModelSelected
    case modelNotDownloaded(String)
    case modelLoadFailed(String)
    case audioFileNotFound(URL)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No transcription model selected. Please download and select a model first."
        case .modelNotDownloaded(let name):
            return "Model '\(name)' is not downloaded."
        case .modelLoadFailed(let detail):
            return "Failed to load model: \(detail)"
        case .audioFileNotFound(let url):
            return "Audio file not found: \(url.lastPathComponent)"
        case .transcriptionFailed(let detail):
            return "Transcription failed: \(detail)"
        }
    }
}
