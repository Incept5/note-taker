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
        You are an expert meeting analyst. You will receive a transcript \(context)\
        of a meeting that lasted approximately \(durationMinutes) minutes.

        Produce a thorough, detailed analysis of the entire meeting. Do NOT be brief — \
        capture the full substance of what was discussed. Your goal is that someone who \
        missed the meeting can read your summary and understand everything that happened.

        Respond with a JSON object with exactly these keys:

        - "summary": A comprehensive narrative overview of the meeting (at least 2-3 paragraphs). \
        Cover the main topics in the order they were discussed, who contributed what, \
        the overall arc of the conversation, and any context needed to understand the discussion. \
        Do not just list topics — explain what was said about each one.

        - "keyPoints": An array of all significant points discussed. Be thorough — include \
        every substantive topic, argument, insight, update, or piece of information shared. \
        Each point should be a complete sentence with enough context to stand on its own.

        - "decisions": An array of every decision, agreement, or conclusion reached. \
        Include what was decided, why (if discussed), and any conditions or caveats mentioned.

        - "actionItems": An array of objects with "task" (string) and "owner" (string or null). \
        Be specific about what needs to be done, any deadlines mentioned, and who volunteered \
        or was assigned. If ownership is unclear, set owner to null but still capture the task.

        - "openQuestions": An array of unresolved questions, disagreements, deferred topics, \
        or anything that was raised but not concluded. Include any topics that someone said \
        they would "get back to" or "follow up on".

        Respond ONLY with valid JSON, no markdown formatting or code fences.
        If a section has no items, use an empty array.
        """
    }

    private func parseSummary(response: String, model: String, duration: TimeInterval) -> MeetingSummary {
        // Try multiple strategies to extract JSON from the response
        let candidates = jsonCandidates(from: response)

        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["summary"] is String {
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

    /// Returns candidate JSON strings extracted from the LLM response, ordered by likelihood.
    private func jsonCandidates(from response: String) -> [String] {
        var candidates: [String] = []
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Raw response as-is
        candidates.append(trimmed)

        // 2. Strip markdown code fences
        let stripped = stripCodeFences(trimmed)
        if stripped != trimmed {
            candidates.append(stripped)
        }

        // 3. Extract the outermost { ... } JSON object from surrounding text
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}") {
            let extracted = String(trimmed[firstBrace...lastBrace])
            if extracted != trimmed {
                candidates.append(extracted)
            }
        }

        return candidates
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
