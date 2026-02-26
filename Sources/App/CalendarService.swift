import EventKit
import OSLog

struct CalendarMeeting {
    let title: String
    let participants: [String]
    let organizer: String?
    let eventIdentifier: String
}

final class CalendarService {
    private let store = EKEventStore()
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "CalendarService")

    func requestAccess() async -> Bool {
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        logger.info("Calendar authorization status before request: \(String(describing: currentStatus), privacy: .public)")

        if currentStatus == .fullAccess {
            return true
        }

        do {
            let granted = try await store.requestFullAccessToEvents()
            logger.info("Calendar access request result: \(granted)")
            return granted
        } catch {
            logger.warning("Calendar access request failed: \(error.localizedDescription)")
            return false
        }
    }

    func findCurrentMeeting(around date: Date, appName: String?) -> CalendarMeeting? {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            logger.warning("Calendar access not granted (status: \(String(describing: status), privacy: .public)), skipping lookup")
            return nil
        }

        let window: TimeInterval = 15 * 60 // 15 minutes
        let startDate = date.addingTimeInterval(-window)
        let endDate = date.addingTimeInterval(window)

        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = store.events(matching: predicate)

        logger.info("Found \(events.count) calendar events in ±15min window")
        for event in events {
            logger.debug("  Event: \(event.title ?? "nil", privacy: .public) (\(event.startDate, privacy: .public) – \(event.endDate, privacy: .public)), attendees: \(event.attendees?.count ?? 0)")
        }

        // Filter to events currently in progress
        let inProgress = events.filter { event in
            event.startDate <= date && event.endDate >= date
        }

        logger.info("\(inProgress.count) events currently in progress")

        guard !inProgress.isEmpty else { return nil }

        // If multiple matches, prefer one whose title contains the app name
        let best: EKEvent
        if let appName, let match = inProgress.first(where: { event in
            event.title?.localizedCaseInsensitiveContains(appName) == true
        }) {
            best = match
        } else {
            // Pick the one with the closest start time
            best = inProgress.min(by: { abs($0.startDate.timeIntervalSince(date)) < abs($1.startDate.timeIntervalSince(date)) })!
        }

        let participants = extractParticipants(from: best)
        let organizer = best.organizer?.name ?? best.organizer?.url.absoluteString

        logger.info("Found calendar event: \(best.title ?? "Untitled", privacy: .public) with \(participants.count) participants")

        return CalendarMeeting(
            title: best.title ?? "Untitled",
            participants: participants,
            organizer: organizer,
            eventIdentifier: best.eventIdentifier
        )
    }

    /// Try EventKit first, then fall back to Google Calendar API if configured and signed in.
    @MainActor
    func findCurrentMeetingWithFallback(
        around date: Date,
        appName: String?,
        googleAuthService: GoogleCalendarAuthService
    ) async -> CalendarMeeting? {
        // Try EventKit first (zero-cost for synced calendars)
        let hasAccess = await requestAccess()
        if hasAccess, let meeting = findCurrentMeeting(around: date, appName: appName) {
            logger.info("Found meeting via EventKit: \(meeting.title, privacy: .public)")
            return meeting
        }

        // Fall back to Google Calendar if configured and signed in
        guard GoogleCalendarConfig.isConfigured, googleAuthService.isSignedIn else {
            return nil
        }

        logger.info("EventKit found no events, trying Google Calendar API")
        do {
            let accessToken = try await googleAuthService.validAccessToken()
            let client = GoogleCalendarClient()
            let events = try await client.fetchEvents(accessToken: accessToken, around: date)

            logger.info("Google Calendar returned \(events.count) events")

            // Filter to events currently in progress
            let inProgress = events.filter { event in
                event.start <= date && event.end >= date
            }

            guard !inProgress.isEmpty else { return nil }

            // Prefer event whose title contains the app name
            let best: GoogleCalendarEvent
            if let appName, let match = inProgress.first(where: {
                $0.summary.localizedCaseInsensitiveContains(appName)
            }) {
                best = match
            } else {
                best = inProgress.min(by: {
                    abs($0.start.timeIntervalSince(date)) < abs($1.start.timeIntervalSince(date))
                })!
            }

            let participants = best.attendees.compactMap { attendee -> String? in
                guard !attendee.isSelf else { return nil }
                return attendee.displayName ?? attendee.email
            }

            logger.info("Found Google Calendar event: \(best.summary, privacy: .public) with \(participants.count) participants")

            return CalendarMeeting(
                title: best.summary,
                participants: participants,
                organizer: nil,
                eventIdentifier: best.id
            )
        } catch {
            logger.warning("Google Calendar fallback failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func extractParticipants(from event: EKEvent) -> [String] {
        guard let attendees = event.attendees else { return [] }
        return attendees.compactMap { participant -> String? in
            if let name = participant.name, !name.isEmpty {
                return name
            }
            // Fall back to email from the URL (format: mailto:user@example.com)
            if case let email = participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
               !email.isEmpty {
                return email
            }
            return nil
        }
    }
}
