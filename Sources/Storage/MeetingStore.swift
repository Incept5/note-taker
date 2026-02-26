import Foundation
import GRDB
import OSLog

@MainActor
final class MeetingStore: ObservableObject {
    @Published var recentMeetings: [MeetingRecord] = []

    private let dbQueue: DatabaseQueue
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "MeetingStore")

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
        loadRecentMeetings()
    }

    // MARK: - CRUD

    @discardableResult
    func createMeeting(startedAt: Date, appName: String?, audio: CapturedAudio) throws -> MeetingRecord {
        var record = MeetingRecord.create(startedAt: startedAt, appName: appName, audio: audio)
        try dbQueue.write { db in
            try record.insert(db)
        }
        logger.info("Created meeting \(record.id)")
        loadRecentMeetings()
        return record
    }

    func updateWithRecordingComplete(id: String, duration: TimeInterval) throws {
        try dbQueue.write { db in
            guard var record = try MeetingRecord.fetchOne(db, key: id) else {
                throw StorageError.meetingNotFound(id)
            }
            record.durationSeconds = duration
            record.status = "stopped"
            try record.update(db)
        }
        loadRecentMeetings()
    }

    func updateWithTranscription(id: String, transcription: MeetingTranscription) throws {
        let json = try JSONEncoder().encode(transcription)
        let jsonString = String(data: json, encoding: .utf8)

        try dbQueue.write { db in
            guard var record = try MeetingRecord.fetchOne(db, key: id) else {
                throw StorageError.meetingNotFound(id)
            }
            record.combinedTranscript = transcription.combinedText
            record.transcriptionJSON = jsonString
            record.transcriptionModelUsed = transcription.modelUsed
            record.transcriptionDuration = transcription.processingDuration
            record.status = "transcribed"
            try record.update(db)
        }
        logger.info("Updated meeting \(id) with transcription")
        loadRecentMeetings()
    }

    func updateWithSummary(id: String, summary: MeetingSummary) throws {
        let json = try JSONEncoder().encode(summary)
        let jsonString = String(data: json, encoding: .utf8)

        try dbQueue.write { db in
            guard var record = try MeetingRecord.fetchOne(db, key: id) else {
                throw StorageError.meetingNotFound(id)
            }
            record.summaryJSON = jsonString
            record.summarizationModelUsed = summary.modelUsed
            record.summarizationDuration = summary.processingDuration
            record.status = "summarized"
            try record.update(db)
        }
        logger.info("Updated meeting \(id) with summary")
        loadRecentMeetings()
    }

    func updateWithCalendarInfo(id: String, calendarTitle: String?, participants: [String]) throws {
        let participantsJSON: String? = {
            guard let data = try? JSONEncoder().encode(participants) else { return nil }
            return String(data: data, encoding: .utf8)
        }()

        try dbQueue.write { db in
            guard var record = try MeetingRecord.fetchOne(db, key: id) else {
                throw StorageError.meetingNotFound(id)
            }
            record.calendarTitle = calendarTitle
            record.participantsJSON = participantsJSON
            try record.update(db)
        }
        logger.info("Updated meeting \(id) with calendar info")
        loadRecentMeetings()
    }

    func updateStatus(id: String, status: String) throws {
        try dbQueue.write { db in
            guard var record = try MeetingRecord.fetchOne(db, key: id) else {
                throw StorageError.meetingNotFound(id)
            }
            record.status = status
            try record.update(db)
        }
        loadRecentMeetings()
    }

    func deleteMeeting(id: String) throws {
        // Fetch the record first for file cleanup
        let record = try dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: id)
        }

        // Delete DB row
        try dbQueue.write { db in
            _ = try MeetingRecord.deleteOne(db, key: id)
        }

        // Best-effort file cleanup
        if let dirURL = record?.recordingDirectoryURL {
            do {
                try FileManager.default.removeItem(at: dirURL)
                logger.info("Deleted recording directory: \(dirURL.path, privacy: .public)")
            } catch {
                logger.warning("Failed to delete recording directory: \(error.localizedDescription)")
            }
        }

        logger.info("Deleted meeting \(id)")
        loadRecentMeetings()
    }

    func loadMeeting(id: String) throws -> MeetingRecord? {
        try dbQueue.read { db in
            try MeetingRecord.fetchOne(db, key: id)
        }
    }

    func loadRecentMeetings(limit: Int = 50) {
        do {
            recentMeetings = try dbQueue.read { db in
                try MeetingRecord
                    .order(Column("startedAt").desc)
                    .limit(limit)
                    .fetchAll(db)
            }
        } catch {
            logger.error("Failed to load meetings: \(error.localizedDescription)")
            recentMeetings = []
        }
    }
}
