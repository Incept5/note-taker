import Foundation

enum SummarizationBackend: String {
    case mlx
    case ollama
}

@MainActor
final class SummarizationService: ObservableObject {
    @Published var progress: Double = 0
    @Published var progressText: String = ""

    private(set) var ollamaClient: OllamaClient
    var selectedModel: String?

    let mlxClient = MLXClient()
    var backend: SummarizationBackend = .mlx
    var selectedMLXModelId: String?

    init(ollamaBaseURL: String = OllamaClient.defaultBaseURL) {
        ollamaClient = OllamaClient(baseURL: ollamaBaseURL)
    }

    func updateBaseURL(_ url: String) {
        ollamaClient = OllamaClient(baseURL: url)
    }

    /// Custom system prompt override. When set, replaces the default built-in prompt.
    var customSystemPrompt: String?

    func summarize(transcript: String, appName: String?, duration: TimeInterval, participants: [String]? = nil) async throws -> MeetingSummary {
        switch backend {
        case .ollama:
            return try await summarizeWithOllama(transcript: transcript, appName: appName, duration: duration, participants: participants)
        case .mlx:
            return try await summarizeWithMLX(transcript: transcript, appName: appName, duration: duration, participants: participants)
        }
    }

    private func summarizeWithOllama(transcript: String, appName: String?, duration: TimeInterval, participants: [String]? = nil) async throws -> MeetingSummary {
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

        let systemPrompt = buildSystemPrompt(appName: appName, duration: duration, participants: participants)

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

    private func summarizeWithMLX(transcript: String, appName: String?, duration: TimeInterval, participants: [String]? = nil) async throws -> MeetingSummary {
        let start = Date()

        guard let modelId = selectedMLXModelId else {
            throw SummarizationError.mlxModelNotSelected
        }

        progress = 0.1
        progressText = "Loading MLX model..."

        do {
            try await mlxClient.ensureModelLoaded(id: modelId)
        } catch {
            throw SummarizationError.mlxLoadFailed(error)
        }

        progress = 0.2
        progressText = "Summarizing with MLX..."

        let systemPrompt = buildSystemPrompt(appName: appName, duration: duration, participants: participants)

        let response: String
        do {
            response = try await mlxClient.chat(systemPrompt: systemPrompt, userMessage: transcript)
        } catch {
            throw SummarizationError.requestFailed(error)
        }

        progress = 0.9
        progressText = "Parsing summary..."

        let displayName = modelId.components(separatedBy: "/").last ?? modelId
        let processingDuration = Date().timeIntervalSince(start)
        let summary = parseSummary(response: response, model: displayName, duration: processingDuration)

        progress = 1.0
        progressText = "Done"

        return summary
    }

    func listModels() async throws -> [OllamaModel] {
        try await ollamaClient.listModels()
    }

    /// The default system prompt used when no custom prompt is set.
    static let defaultSystemPromptTemplate = """
    You are an expert meeting analyst. You will receive a transcript {{context}}\
    of a meeting that lasted approximately {{duration}} minutes.{{participants}}

    Produce a thorough, detailed analysis of the entire meeting. Your goal is that someone \
    who missed the meeting can read your summary and understand everything that happened.

    Respond with a JSON object with exactly these keys:

    - "overview": A concise 1-2 sentence summary of what the meeting covered and who attended.

    - "keyDecisions": An array of specific decisions made during the meeting. Include \
    context on why each decision was made when discussed.

    - "actionItems": An array of objects with "task" (string) and "owner" (string or null). \
    Be specific about what needs to be done, any deadlines mentioned, and who volunteered \
    or was assigned. Group related tasks per person. If ownership is unclear, set owner \
    to null but still capture the task.

    - "discussionHighlights": An array of objects with "topic" (string) and "detail" (string). \
    Each major discussion topic gets a short descriptive name as "topic" and a detailed \
    paragraph as "detail" explaining what was discussed, by whom, and what conclusions \
    were reached. Be thorough — capture the full substance of each topic.

    - "blockers": An array of current blockers preventing progress that were mentioned \
    in the meeting. If none were discussed, use an empty array.

    - "nextSteps": An array of concrete next steps with timing where mentioned. These \
    are forward-looking items that aren't necessarily assigned to a specific person.

    Respond ONLY with valid JSON, no markdown formatting or code fences.
    If a section has no items, use an empty array.
    """

    private func buildSystemPrompt(appName: String?, duration: TimeInterval, participants: [String]? = nil) -> String {
        let durationMinutes = Int(duration / 60)
        let context = appName.map { "from \($0) " } ?? ""
        let participantLine: String
        if let participants, !participants.isEmpty {
            participantLine = "\n\nThe meeting participants are: \(participants.joined(separator: ", ")). Use these names when attributing action items and contributions."
        } else {
            participantLine = ""
        }

        let template = customSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? customSystemPrompt!
            : Self.defaultSystemPromptTemplate

        return template
            .replacingOccurrences(of: "{{context}}", with: context)
            .replacingOccurrences(of: "{{duration}}", with: "\(durationMinutes)")
            .replacingOccurrences(of: "{{participants}}", with: participantLine)
    }

    private func parseSummary(response: String, model: String, duration: TimeInterval) -> MeetingSummary {
        // Try multiple strategies to extract JSON from the response
        let candidates = jsonCandidates(from: response)

        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Accept either new format (overview) or old format (summary)
                let hasNewFormat = json["overview"] is String
                let hasOldFormat = json["summary"] is String
                guard hasNewFormat || hasOldFormat else { continue }

                return cleanSummary(MeetingSummary(
                    overview: json["overview"] as? String,
                    keyDecisions: json["keyDecisions"] as? [String],
                    discussionHighlights: parseDiscussionTopics(json["discussionHighlights"]),
                    blockers: json["blockers"] as? [String],
                    nextSteps: json["nextSteps"] as? [String],
                    actionItems: parseActionItems(json["actionItems"]),
                    modelUsed: model,
                    processingDuration: duration,
                    summary: json["summary"] as? String,
                    keyPoints: json["keyPoints"] as? [String],
                    decisions: json["decisions"] as? [String],
                    openQuestions: json["openQuestions"] as? [String]
                ))
            }
        }

        // Try regex extraction of individual JSON fields (quoted values)
        if let regexSummary = extractRegexSummary(from: response, model: model, duration: duration) {
            return cleanSummary(regexSummary)
        }

        // Try loose-format extraction for models that return "key":\n bullet lists
        if let looseSummary = extractLooseFormatSummary(from: response, model: model, duration: duration) {
            return cleanSummary(looseSummary)
        }

        // Fallback: treat entire response as summary text
        return cleanSummary(MeetingSummary(
            overview: nil,
            keyDecisions: nil,
            discussionHighlights: nil,
            blockers: nil,
            nextSteps: nil,
            actionItems: [],
            modelUsed: model,
            processingDuration: duration,
            summary: response,
            keyPoints: nil,
            decisions: nil,
            openQuestions: nil
        ))
    }

    /// Cleans JSON artifacts from parsed summary fields — brackets, literal \n\n, raw JSON fragments.
    private func cleanSummary(_ summary: MeetingSummary) -> MeetingSummary {
        MeetingSummary(
            overview: summary.overview.map { cleanSummaryText($0) },
            keyDecisions: summary.keyDecisions.map { cleanStringArray($0) },
            discussionHighlights: summary.discussionHighlights?.map {
                DiscussionTopic(topic: cleanSummaryText($0.topic), detail: cleanSummaryText($0.detail))
            },
            blockers: summary.blockers.map { cleanStringArray($0) },
            nextSteps: summary.nextSteps.map { cleanStringArray($0) },
            actionItems: cleanActionItems(summary.actionItems),
            modelUsed: summary.modelUsed,
            processingDuration: summary.processingDuration,
            summary: summary.summary.map { cleanSummaryText($0) },
            keyPoints: summary.keyPoints.map { cleanStringArray($0) },
            decisions: summary.decisions.map { cleanStringArray($0) },
            openQuestions: summary.openQuestions.map { cleanStringArray($0) }
        )
    }

    private func parseDiscussionTopics(_ value: Any?) -> [DiscussionTopic]? {
        guard let items = value as? [[String: Any]] else { return nil }
        let topics = items.compactMap { dict -> DiscussionTopic? in
            guard let topic = dict["topic"] as? String,
                  let detail = dict["detail"] as? String else { return nil }
            return DiscussionTopic(topic: topic, detail: detail)
        }
        return topics.isEmpty ? nil : topics
    }

    /// Cleans the narrative summary text of literal escape sequences and JSON artifacts.
    private func cleanSummaryText(_ text: String) -> String {
        var result = text
        // Replace literal \n with actual newlines (when the model outputs backslash-n as text)
        result = result.replacingOccurrences(of: "\\n\\n", with: "\n\n")
        result = result.replacingOccurrences(of: "\\n", with: "\n")
        result = result.replacingOccurrences(of: "\\t", with: " ")
        // Remove stray JSON brackets at start/end
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("[") && !result.hasPrefix("[!") { result = String(result.dropFirst()) }
        if result.hasSuffix("]") { result = String(result.dropLast()) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Filters out JSON artifact items and cleans remaining items.
    private func cleanStringArray(_ items: [String]) -> [String] {
        items.compactMap { item -> String? in
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            // Filter out items that are just JSON syntax or escape sequences
            let junkPatterns: Set<String> = ["[", "]", "{", "}", ",", "\\n", "\\n\\n", "\\r", "\\t", ""]
            if junkPatterns.contains(trimmed) { return nil }
            // Filter items that are just whitespace or punctuation
            if trimmed.allSatisfy({ "[]{}(),\\\"'\n\r\t ".contains($0) }) { return nil }
            // Filter raw JSON key-value fragments like `"task": "..."` or `owner": "...`
            if trimmed.range(of: #"^"?(task|owner)"?\s*:"#, options: .regularExpression) != nil { return nil }
            // Clean literal escape sequences within the item text
            var cleaned = trimmed
            cleaned = cleaned.replacingOccurrences(of: "\\n", with: " ")
            cleaned = cleaned.replacingOccurrences(of: "\\t", with: " ")
            // Remove wrapping quotes
            if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 1 {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            // Remove trailing commas (from JSON arrays)
            if cleaned.hasSuffix(",") { cleaned = String(cleaned.dropLast()) }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    /// Cleans action items — filters junk and tries to salvage raw JSON fragment action items.
    private func cleanActionItems(_ items: [ActionItem]) -> [ActionItem] {
        items.compactMap { item -> ActionItem? in
            let task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)
            let junkPatterns: Set<String> = ["[", "]", "{", "}", ",", "\\n", "\\n\\n", ""]
            if junkPatterns.contains(task) { return nil }
            if task.allSatisfy({ "[]{}(),\\\"'\n\r\t ".contains($0) }) { return nil }
            var cleanedTask = task
                .replacingOccurrences(of: "\\n", with: " ")
                .replacingOccurrences(of: "\\t", with: " ")
            if cleanedTask.hasSuffix(",") { cleanedTask = String(cleanedTask.dropLast()) }
            if cleanedTask.hasPrefix("\"") && cleanedTask.hasSuffix("\"") && cleanedTask.count > 1 {
                cleanedTask = String(cleanedTask.dropFirst().dropLast())
            }
            cleanedTask = cleanedTask.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedTask.isEmpty else { return nil }

            var cleanedOwner = item.owner?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            if let owner = cleanedOwner, owner.isEmpty || owner == "null" || owner == "none" {
                cleanedOwner = nil
            }
            return ActionItem(task: cleanedTask, owner: cleanedOwner)
        }
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

        // 4. Fix unescaped newlines inside JSON string values — LLMs often produce
        //    literal newlines within strings which makes JSONSerialization reject the payload.
        //    Escape any newline/tab that appears between quotes.
        for base in [trimmed, stripped] {
            let fixed = fixUnescapedNewlines(in: base)
            if fixed != base {
                candidates.append(fixed)
            }
        }

        return candidates
    }

    /// Escapes literal newlines and tabs that appear inside JSON string values.
    private func fixUnescapedNewlines(in text: String) -> String {
        var result = ""
        var insideString = false
        var prevWasBackslash = false
        for char in text {
            if insideString {
                if char == "\\" && !prevWasBackslash {
                    prevWasBackslash = true
                    result.append(char)
                    continue
                }
                if char == "\"" && !prevWasBackslash {
                    insideString = false
                    result.append(char)
                } else if char == "\n" {
                    result.append("\\n")
                } else if char == "\r" {
                    result.append("\\r")
                } else if char == "\t" {
                    result.append("\\t")
                } else {
                    result.append(char)
                }
                prevWasBackslash = false
            } else {
                if char == "\"" {
                    insideString = true
                }
                result.append(char)
                prevWasBackslash = false
            }
        }
        return result
    }

    private func parseActionItems(_ value: Any?) -> [ActionItem] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { dict in
            guard let task = dict["task"] as? String else { return nil }
            let owner = dict["owner"] as? String
            return ActionItem(task: task, owner: owner)
        }
    }

    /// Last-resort extraction: pull individual fields from the response using regex patterns
    /// when the full JSON fails to parse (e.g. deeply malformed but still has recognizable structure).
    private func extractRegexSummary(from response: String, model: String, duration: TimeInterval) -> MeetingSummary? {
        // Try new format first (overview), then old format (summary)
        let overviewMatch = extractJSONStringValue(key: "overview", from: response)
        let summaryMatch = extractJSONStringValue(key: "summary", from: response)

        guard (overviewMatch != nil && !overviewMatch!.isEmpty) ||
              (summaryMatch != nil && !summaryMatch!.isEmpty) else {
            return nil
        }

        return MeetingSummary(
            overview: overviewMatch,
            keyDecisions: extractJSONArrayOfStrings(key: "keyDecisions", from: response).nilIfEmpty,
            discussionHighlights: nil, // too complex for regex
            blockers: extractJSONArrayOfStrings(key: "blockers", from: response).nilIfEmpty,
            nextSteps: extractJSONArrayOfStrings(key: "nextSteps", from: response).nilIfEmpty,
            actionItems: parseActionItems(nil),
            modelUsed: model,
            processingDuration: duration,
            summary: summaryMatch,
            keyPoints: extractJSONArrayOfStrings(key: "keyPoints", from: response).nilIfEmpty,
            decisions: extractJSONArrayOfStrings(key: "decisions", from: response).nilIfEmpty,
            openQuestions: extractJSONArrayOfStrings(key: "openQuestions", from: response).nilIfEmpty
        )
    }

    /// Extracts the string value for a given key from a JSON-like string, handling unescaped newlines.
    private func extractJSONStringValue(key: String, from text: String) -> String? {
        // Find "key" : "value..." handling the fact that value may contain unescaped newlines
        guard let keyRange = text.range(of: "\"\(key)\"") else { return nil }
        let afterKey = text[keyRange.upperBound...]

        // Skip whitespace and colon
        guard let colonIndex = afterKey.firstIndex(of: ":") else { return nil }
        let afterColon = afterKey[afterKey.index(after: colonIndex)...]
            .drop(while: { $0.isWhitespace || $0.isNewline })

        guard afterColon.first == "\"" else { return nil }

        // Walk forward to find the closing quote (not preceded by backslash)
        // But we need to handle that the closing " is followed by , or \n or }
        var result = ""
        var idx = afterColon.index(after: afterColon.startIndex)
        var prevWasBackslash = false
        while idx < afterColon.endIndex {
            let ch = afterColon[idx]
            if ch == "\\" && !prevWasBackslash {
                prevWasBackslash = true
                idx = afterColon.index(after: idx)
                continue
            }
            if ch == "\"" && !prevWasBackslash {
                break
            }
            if prevWasBackslash {
                // Interpret escape sequence
                switch ch {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                default: result.append(ch)
                }
            } else {
                result.append(ch)
            }
            prevWasBackslash = false
            idx = afterColon.index(after: idx)
        }
        return result.isEmpty ? nil : result
    }

    /// Extracts an array of strings for a given key from a JSON-like string.
    private func extractJSONArrayOfStrings(key: String, from text: String) -> [String] {
        guard let keyRange = text.range(of: "\"\(key)\"") else { return [] }
        let afterKey = text[keyRange.upperBound...]
        guard let openBracket = afterKey.firstIndex(of: "[") else { return [] }
        guard let closeBracket = afterKey[openBracket...].firstIndex(of: "]") else { return [] }
        let arrayContent = String(afterKey[openBracket...closeBracket])

        // Parse the array content with JSONSerialization after fixing newlines
        let fixed = fixUnescapedNewlines(in: arrayContent)
        if let data = fixed.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return arr
        }
        return []
    }

    /// Handles model output in loose key-value format, e.g.:
    ///   "summary":
    ///   Some unquoted paragraph text...
    ///
    ///   "keyPoints":
    ///   * First point
    ///   * Second point
    ///
    /// Splits the response at known JSON key markers and extracts text blocks.
    private func extractLooseFormatSummary(from response: String, model: String, duration: TimeInterval) -> MeetingSummary? {
        let knownKeys = ["overview", "keyDecisions", "actionItems", "discussionHighlights", "blockers", "nextSteps",
                         "summary", "keyPoints", "decisions", "openQuestions"]

        // Check that the response contains at least "overview" or "summary" as a key marker
        guard response.contains("\"overview\"") || response.contains("\"summary\"") else { return nil }

        // Build a map of key -> text content between keys
        var sections: [String: String] = [:]
        for (i, key) in knownKeys.enumerated() {
            guard let keyRange = response.range(of: "\"\(key)\"") else { continue }
            let afterKey = response[keyRange.upperBound...]

            // Skip optional colon and whitespace
            let content: Substring
            if let colonIdx = afterKey.firstIndex(of: ":") {
                content = afterKey[afterKey.index(after: colonIdx)...]
            } else {
                content = afterKey
            }

            // Find where the next key starts (or end of string)
            var endIndex = content.endIndex
            for nextKey in knownKeys[(i + 1)...] {
                if let nextRange = content.range(of: "\"\(nextKey)\"") {
                    endIndex = nextRange.lowerBound
                    break
                }
            }

            let sectionText = String(content[content.startIndex..<endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sectionText.isEmpty {
                sections[key] = sectionText
            }
        }

        // Need at least overview or summary
        let overviewText = sections["overview"]?.trimmingQuotes()
        let summaryText = sections["summary"]?.trimmingQuotes()
        guard (overviewText != nil && !overviewText!.isEmpty) ||
              (summaryText != nil && !summaryText!.isEmpty) else { return nil }

        return MeetingSummary(
            overview: overviewText,
            keyDecisions: extractBulletItems(from: sections["keyDecisions"]).nilIfEmpty,
            discussionHighlights: nil, // can't reliably parse structured topics from loose format
            blockers: extractBulletItems(from: sections["blockers"]).nilIfEmpty,
            nextSteps: extractBulletItems(from: sections["nextSteps"]).nilIfEmpty,
            actionItems: extractLooseActionItems(from: sections["actionItems"]),
            modelUsed: model,
            processingDuration: duration,
            summary: summaryText,
            keyPoints: extractBulletItems(from: sections["keyPoints"]).nilIfEmpty,
            decisions: extractBulletItems(from: sections["decisions"]).nilIfEmpty,
            openQuestions: extractBulletItems(from: sections["openQuestions"]).nilIfEmpty
        )
    }

    /// Extracts bullet items from text using *, -, or numbered list prefixes.
    private func extractBulletItems(from text: String?) -> [String] {
        guard let text, !text.isEmpty else { return [] }
        return text
            .components(separatedBy: "\n")
            .map { line in
                var s = line.trimmingCharacters(in: .whitespaces)
                // Strip bullet prefixes: *, -, •, or "1." / "1)"
                if s.hasPrefix("* ") { s = String(s.dropFirst(2)) }
                else if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
                else if s.hasPrefix("• ") { s = String(s.dropFirst(2)) }
                else if let dotRange = s.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                    s = String(s[dotRange.upperBound...])
                }
                return s.trimmingCharacters(in: .whitespaces)
                    .trimmingQuotes()
            }
            .filter { !$0.isEmpty }
    }

    /// Extract action items from loose text like "Task: ...\nOwner: ..."
    private func extractLooseActionItems(from text: String?) -> [ActionItem] {
        guard let text, !text.isEmpty else { return [] }

        // Try to find "Task:" / "Owner:" pairs
        let lines = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var items: [ActionItem] = []
        var currentTask: String?
        var currentOwner: String?

        for line in lines {
            let stripped = line
                .replacingOccurrences(of: #"^[\*\-•]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if stripped.lowercased().hasPrefix("task:") {
                // Flush previous
                if let task = currentTask {
                    items.append(ActionItem(task: task, owner: cleanOwner(currentOwner)))
                }
                currentTask = String(stripped.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                currentOwner = nil
            } else if stripped.lowercased().hasPrefix("owner:") {
                currentOwner = String(stripped.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if !stripped.isEmpty, currentTask == nil {
                // Treat as a standalone task line
                items.append(ActionItem(task: stripped.trimmingQuotes(), owner: nil))
            }
        }
        // Flush last
        if let task = currentTask {
            items.append(ActionItem(task: task, owner: cleanOwner(currentOwner)))
        }

        return items
    }

    private func cleanOwner(_ owner: String?) -> String? {
        guard let owner, !owner.isEmpty,
              owner.lowercased() != "null",
              owner.lowercased() != "none",
              owner.lowercased() != "n/a" else { return nil }
        return owner
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

private extension String {
    /// Strip matching leading/trailing double quotes from a string value.
    func trimmingQuotes() -> String {
        if hasPrefix("\"") && hasSuffix("\"") && count > 1 {
            return String(dropFirst().dropLast())
        }
        return self
    }
}

extension Array {
    /// Returns nil if the array is empty, otherwise returns self.
    var nilIfEmpty: Self? {
        isEmpty ? nil : self
    }
}
