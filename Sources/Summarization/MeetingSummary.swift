import Foundation

struct MeetingSummary {
    let summary: String
    let keyPoints: [String]
    let decisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]
    let modelUsed: String
    let processingDuration: TimeInterval
}

struct ActionItem {
    let task: String
    let owner: String?
}
