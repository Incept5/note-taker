import Foundation

struct MeetingSummary: Codable {
    let summary: String
    let keyPoints: [String]
    let decisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]
    let modelUsed: String
    let processingDuration: TimeInterval
}

struct ActionItem: Codable {
    let task: String
    let owner: String?
}

extension MeetingSummary {
    func markdownText(participants: [String]? = nil) -> String {
        var text = ""

        if let participants, !participants.isEmpty {
            text += "## Participants\n"
            text += participants.joined(separator: ", ") + "\n\n"
        }

        if !keyPoints.isEmpty {
            text += "## Key Points\n"
            for point in keyPoints {
                text += "- \(point)\n"
            }
        }

        if !decisions.isEmpty {
            if !text.isEmpty { text += "\n" }
            text += "## Decisions\n"
            for decision in decisions {
                text += "- \(decision)\n"
            }
        }

        if !actionItems.isEmpty {
            if !text.isEmpty { text += "\n" }
            text += "## Action Items\n"
            for item in actionItems {
                let owner = item.owner.map { " (@\($0))" } ?? ""
                text += "- [ ] \(item.task)\(owner)\n"
            }
        }

        if !openQuestions.isEmpty {
            if !text.isEmpty { text += "\n" }
            text += "## Open Questions\n"
            for question in openQuestions {
                text += "- \(question)\n"
            }
        }

        if !text.isEmpty { text += "\n" }
        text += "## Summary\n\(summary)\n"

        return text
    }
}
