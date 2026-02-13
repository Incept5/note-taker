import Foundation

enum StorageError: LocalizedError {
    case databaseError(Error)
    case meetingNotFound(String)
    case fileCleanupFailed(Error)

    var errorDescription: String? {
        switch self {
        case .databaseError(let error):
            return "Database error: \(error.localizedDescription)"
        case .meetingNotFound(let id):
            return "Meeting not found: \(id)"
        case .fileCleanupFailed(let error):
            return "File cleanup failed: \(error.localizedDescription)"
        }
    }
}
