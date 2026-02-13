import Foundation
import GRDB

struct MeetingRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "meetings"

    var id: String
    var startedAt: Date
    var durationSeconds: Double?
    var appName: String?
    var systemAudioPath: String?
    var micAudioPath: String?
    var recordingDirectory: String?
    var combinedTranscript: String?
    var transcriptionJSON: String?
    var transcriptionModelUsed: String?
    var transcriptionDuration: Double?
    var summaryJSON: String?
    var summarizationModelUsed: String?
    var summarizationDuration: Double?
    var status: String
    var createdAt: Date

    // MARK: - Factory

    static func create(startedAt: Date, appName: String?, audio: CapturedAudio) -> MeetingRecord {
        MeetingRecord(
            id: UUID().uuidString,
            startedAt: startedAt,
            durationSeconds: nil,
            appName: appName,
            systemAudioPath: audio.systemAudioURL.lastPathComponent,
            micAudioPath: audio.microphoneURL.lastPathComponent,
            recordingDirectory: audio.directory.lastPathComponent,
            combinedTranscript: nil,
            transcriptionJSON: nil,
            transcriptionModelUsed: nil,
            transcriptionDuration: nil,
            summaryJSON: nil,
            summarizationModelUsed: nil,
            summarizationDuration: nil,
            status: "recording",
            createdAt: Date()
        )
    }

    // MARK: - JSON Decoding Helpers

    func decodedTranscription() -> MeetingTranscription? {
        guard let json = transcriptionJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MeetingTranscription.self, from: data)
    }

    func decodedSummary() -> MeetingSummary? {
        guard let json = summaryJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MeetingSummary.self, from: data)
    }

    // MARK: - Computed Properties

    var formattedDuration: String {
        guard let secs = durationSeconds else { return "--:--" }
        let minutes = Int(secs) / 60
        let seconds = Int(secs) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startedAt)
    }

    var recordingDirectoryURL: URL? {
        guard let dir = recordingDirectory else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("NoteTaker", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(dir, isDirectory: true)
    }
}
