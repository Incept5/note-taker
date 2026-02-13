import Foundation

@MainActor
final class SummarizationService: ObservableObject {
    @Published var progress: Double = 0
    @Published var progressText: String = ""

    let ollamaClient = OllamaClient()
    var selectedModel: String?

    func summarize(transcript: String, appName: String?, duration: TimeInterval) async throws -> MeetingSummary {
        let start = Date()

        guard let model = selectedModel else {
            throw SummarizationError.noModelSelected
        }

        progress = 0.1
        progressText = "Connecting to Ollama..."

        guard await ollamaClient.checkAvailability() else {
            throw SummarizationError.ollamaNotRunning
        }

        progress = 0.2
        progressText = "Summarizing with \(model)..."

        let systemPrompt = buildSystemPrompt(appName: appName, duration: duration)

        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": transcript]
        ]

        let response: String
        do {
            response = try await ollamaClient.chat(model: model, messages: messages)
        } catch {
            throw SummarizationError.requestFailed(error)
        }

        progress = 0.9
        progressText = "Parsing summary..."

        let processingDuration = Date().timeIntervalSince(start)
        let summary = parseSummary(response: response, model: model, duration: processingDuration)

        progress = 1.0
        progressText = "Done"

        return summary
    }

    func listModels() async throws -> [OllamaModel] {
        try await ollamaClient.listModels()
    }

    private func buildSystemPrompt(appName: String?, duration: TimeInterval) -> String {
        let durationMinutes = Int(duration / 60)
        let context = appName.map { "from \($0) " } ?? ""

        return """
        You are a meeting summarization assistant. You will receive a transcript \(context)\
        of a meeting that lasted approximately \(durationMinutes) minutes.

        Analyze the transcript and produce a JSON object with exactly these keys:
        - "summary": A concise 2-3 sentence overview of the meeting
        - "keyPoints": An array of the most important points discussed
        - "decisions": An array of decisions that were made
        - "actionItems": An array of objects with "task" (string) and "owner" (string or null)
        - "openQuestions": An array of unresolved questions or topics needing follow-up

        Respond ONLY with valid JSON, no markdown formatting or code fences.
        If a section has no items, use an empty array.
        """
    }

    private func parseSummary(response: String, model: String, duration: TimeInterval) -> MeetingSummary {
        // Try to parse as JSON first
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return MeetingSummary(
                summary: json["summary"] as? String ?? response,
                keyPoints: json["keyPoints"] as? [String] ?? [],
                decisions: json["decisions"] as? [String] ?? [],
                actionItems: parseActionItems(json["actionItems"]),
                openQuestions: json["openQuestions"] as? [String] ?? [],
                modelUsed: model,
                processingDuration: duration
            )
        }

        // Try stripping markdown code fences and re-parsing
        let stripped = stripCodeFences(response)
        if stripped != response,
           let data = stripped.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return MeetingSummary(
                summary: json["summary"] as? String ?? response,
                keyPoints: json["keyPoints"] as? [String] ?? [],
                decisions: json["decisions"] as? [String] ?? [],
                actionItems: parseActionItems(json["actionItems"]),
                openQuestions: json["openQuestions"] as? [String] ?? [],
                modelUsed: model,
                processingDuration: duration
            )
        }

        // Fallback: treat entire response as summary text
        return MeetingSummary(
            summary: response,
            keyPoints: [],
            decisions: [],
            actionItems: [],
            openQuestions: [],
            modelUsed: model,
            processingDuration: duration
        )
    }

    private func parseActionItems(_ value: Any?) -> [ActionItem] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard let task = dict["task"] as? String else { return nil }
            let owner = dict["owner"] as? String
            return ActionItem(task: task, owner: owner)
        }
    }

    private func stripCodeFences(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove ```json ... ``` or ``` ... ```
        if result.hasPrefix("```") {
            if let firstNewline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: firstNewline)...])
            }
            if result.hasSuffix("```") {
                result = String(result.dropLast(3))
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
