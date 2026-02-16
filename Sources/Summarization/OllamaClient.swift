import Foundation

struct OllamaModel {
    let name: String
    let size: Int64
    let parameterSize: String
}

final class OllamaClient {
    static let defaultBaseURL = "http://localhost:11434"

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: String = OllamaClient.defaultBaseURL) {
        self.baseURL = URL(string: baseURL) ?? URL(string: OllamaClient.defaultBaseURL)!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for slow summarization
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
    }

    func checkAvailability() async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5 // Quick check
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func listModels() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await session.data(from: url)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SummarizationError.ollamaNotRunning
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw SummarizationError.invalidResponse
        }

        return models.compactMap { dict in
            guard let name = dict["name"] as? String else { return nil }
            let size = dict["size"] as? Int64 ?? 0
            let details = dict["details"] as? [String: Any]
            let parameterSize = details?["parameter_size"] as? String ?? ""
            return OllamaModel(name: name, size: size, parameterSize: parameterSize)
        }
    }

    func chat(model: String, messages: [[String: String]]) async throws -> String {
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": false
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SummarizationError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SummarizationError.invalidResponse
        }

        return content
    }
}
