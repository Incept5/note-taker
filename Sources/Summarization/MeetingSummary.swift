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
