import Foundation
import OSLog

/// Polls the calendar at regular intervals to detect upcoming meetings and trigger auto-recording.
@MainActor
final class CalendarPollingService {
    private let calendarService: CalendarService
    private let googleAuthService: GoogleCalendarAuthService
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "CalendarPollingService")

    private var pollTimer: Timer?
    /// How often to poll (seconds).
    private static let pollInterval: TimeInterval = 60
    /// How far ahead to look for events (minutes).
    private static let lookAheadMinutes = 3

    /// Called when an upcoming meeting is detected that should trigger recording.
    var onUpcomingMeeting: ((CalendarMeeting) -> Void)?

    init(calendarService: CalendarService, googleAuthService: GoogleCalendarAuthService) {
        self.calendarService = calendarService
        self.googleAuthService = googleAuthService
    }

    func start() {
        guard pollTimer == nil else { return }
        logger.info("Starting calendar polling (every \(Self.pollInterval)s, \(Self.lookAheadMinutes)min look-ahead)")

        // Poll immediately, then on interval
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        logger.info("Stopped calendar polling")
    }

    var isRunning: Bool { pollTimer != nil }

    private func poll() {
        Task {
            let meetings = await calendarService.fetchUpcomingMeetings(
                withinMinutes: Self.lookAheadMinutes,
                googleAuthService: googleAuthService
            )

            let now = Date()
            for meeting in meetings {
                // Only trigger for events starting within the next 2 minutes
                // or that started within the last 60 seconds
                let timeUntilStart = meeting.start.timeIntervalSince(now)
                guard timeUntilStart <= 120, timeUntilStart >= -60 else { continue }

                logger.info("Upcoming meeting detected: \(meeting.title, privacy: .public) (starts in \(Int(timeUntilStart))s)")
                onUpcomingMeeting?(meeting)
            }
        }
    }
}
