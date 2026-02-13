import Foundation
import GRDB
import OSLog

final class DatabaseManager {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "DatabaseManager")

    private init() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbDir = appSupport.appendingPathComponent("NoteTaker", isDirectory: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

            let dbPath = dbDir.appendingPathComponent("notetaker.db").path

            let config = Configuration()

            dbQueue = try DatabaseQueue(path: dbPath, configuration: config)
            try migrate()
            logger.info("Database opened at \(dbPath, privacy: .public)")
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_create_meetings") { db in
            try db.create(table: "meetings") { t in
                t.primaryKey("id", .text)
                t.column("startedAt", .datetime).notNull()
                t.column("durationSeconds", .double)
                t.column("appName", .text)
                t.column("systemAudioPath", .text)
                t.column("micAudioPath", .text)
                t.column("recordingDirectory", .text)
                t.column("combinedTranscript", .text)
                t.column("transcriptionJSON", .text)
                t.column("transcriptionModelUsed", .text)
                t.column("transcriptionDuration", .double)
                t.column("summaryJSON", .text)
                t.column("summarizationModelUsed", .text)
                t.column("summarizationDuration", .double)
                t.column("status", .text).notNull().defaults(to: "recording")
                t.column("createdAt", .datetime).notNull().defaults(sql: "CURRENT_TIMESTAMP")
            }
        }

        try migrator.migrate(dbQueue)
    }
}
