import Foundation

struct DiscussionTopic: Codable {
    let topic: String
    let detail: String
}

struct ActionItem: Codable {
    let task: String
    let owner: String?
}

struct MeetingSummary: Codable {
    // New fields
    let overview: String?
    let keyDecisions: [String]?
    let discussionHighlights: [DiscussionTopic]?
    let blockers: [String]?
    let nextSteps: [String]?

    // Shared fields
    let actionItems: [ActionItem]
    let modelUsed: String
    let processingDuration: TimeInterval

    // Old fields (for backward compat with existing DB records)
    let summary: String?
    let keyPoints: [String]?
    let decisions: [String]?
    let openQuestions: [String]?

    // MARK: - Computed accessors with fallbacks for old data

    var effectiveOverview: String {
        if let overview, !overview.isEmpty { return overview }
        if let summary, !summary.isEmpty { return summary }
        return ""
    }

    var effectiveKeyDecisions: [String] {
        if let keyDecisions, !keyDecisions.isEmpty { return keyDecisions }
        if let decisions, !decisions.isEmpty { return decisions }
        return []
    }

    var effectiveDiscussionHighlights: [DiscussionTopic] {
        if let discussionHighlights, !discussionHighlights.isEmpty { return discussionHighlights }
        // Map old keyPoints into discussion topics as fallback
        if let keyPoints, !keyPoints.isEmpty {
            return keyPoints.map { DiscussionTopic(topic: "Key Point", detail: $0) }
        }
        return []
    }

    var effectiveBlockers: [String] {
        blockers ?? []
    }

    var effectiveNextSteps: [String] {
        nextSteps ?? []
    }

    var effectiveOpenQuestions: [String] {
        openQuestions ?? []
    }

    /// Whether this summary uses the new format (has overview or discussionHighlights)
    var isNewFormat: Bool {
        (overview != nil && !(overview?.isEmpty ?? true)) ||
        (discussionHighlights != nil && !(discussionHighlights?.isEmpty ?? true))
    }
}

extension MeetingSummary {
    func markdownText(participants: [String]? = nil) -> String {
        var text = ""

        if let participants, !participants.isEmpty {
            text += "## Participants\n"
            text += participants.joined(separator: ", ") + "\n\n"
        }

        // Overview
        let overviewText = effectiveOverview
        if !overviewText.isEmpty {
            text += "## Overview\n\(overviewText)\n\n"
        }

        // Key Decisions
        let decisions = effectiveKeyDecisions
        if !decisions.isEmpty {
            text += "## Key Decisions\n"
            for (i, decision) in decisions.enumerated() {
                text += "\(i + 1). \(decision)\n"
            }
            text += "\n"
        }

        // Action Items
        if !actionItems.isEmpty {
            text += "## Action Items\n"
            for item in actionItems {
                if let owner = item.owner, !owner.isEmpty {
                    text += "- **\(owner):** \(item.task)\n"
                } else {
                    text += "- [ ] \(item.task)\n"
                }
            }
            text += "\n"
        }

        // Discussion Highlights
        let highlights = effectiveDiscussionHighlights
        if !highlights.isEmpty && isNewFormat {
            text += "## Discussion Highlights\n"
            for topic in highlights {
                text += "### \(topic.topic)\n\(topic.detail)\n\n"
            }
        }

        // Blockers
        let blockerList = effectiveBlockers
        if !blockerList.isEmpty {
            text += "## Blockers\n"
            for blocker in blockerList {
                text += "- \(blocker)\n"
            }
            text += "\n"
        }

        // Next Steps
        let steps = effectiveNextSteps
        if !steps.isEmpty {
            text += "## Next Steps\n"
            for step in steps {
                text += "- \(step)\n"
            }
            text += "\n"
        }

        // Open Questions (old format fallback)
        let questions = effectiveOpenQuestions
        if !questions.isEmpty {
            text += "## Open Questions\n"
            for question in questions {
                text += "- \(question)\n"
            }
            text += "\n"
        }

        // For old-format summaries, include key points and full summary narrative
        if !isNewFormat {
            if let keyPoints, !keyPoints.isEmpty {
                text += "## Key Points\n"
                for point in keyPoints {
                    text += "- \(point)\n"
                }
                text += "\n"
            }

            if let summary, !summary.isEmpty, overview == nil {
                // Already rendered as overview above if overview was nil
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}
