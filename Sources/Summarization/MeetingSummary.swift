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
    var markdownText: String {
        var text = "## Summary\n\(summary)\n"

        if !keyPoints.isEmpty {
            text += "\n## Key Points\n"
            for point in keyPoints {
                text += "- \(point)\n"
            }
        }

        if !decisions.isEmpty {
            text += "\n## Decisions\n"
            for decision in decisions {
                text += "- \(decision)\n"
            }
        }

        if !actionItems.isEmpty {
            text += "\n## Action Items\n"
            for item in actionItems {
                let owner = item.owner.map { " (@\($0))" } ?? ""
                text += "- [ ] \(item.task)\(owner)\n"
            }
        }

        if !openQuestions.isEmpty {
            text += "\n## Open Questions\n"
            for question in openQuestions {
                text += "- \(question)\n"
            }
        }

        return text
    }
}
