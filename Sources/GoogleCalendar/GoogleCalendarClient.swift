import Foundation
import OSLog

enum GoogleCalendarError: LocalizedError {
    case httpError(Int, String)
    case invalidResponse
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg): "Google Calendar API error \(code): \(msg)"
        case .invalidResponse: "Invalid response from Google Calendar API"
        case .unauthorized: "Google Calendar access unauthorized — please sign in again"
        }
    }
}

struct GoogleCalendarAttendee {
    let email: String
    let displayName: String?
    let isSelf: Bool
}

struct GoogleCalendarEvent {
    let id: String
    let summary: String
    let start: Date
    let end: Date
    let attendees: [GoogleCalendarAttendee]
}

struct GoogleCalendarClient {
    private static let baseURL = "https://www.googleapis.com/calendar/v3"
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "GoogleCalendarClient")

    /// Fetch events from the user's primary calendar in a time window around `date`.
    func fetchEvents(accessToken: String, around date: Date, windowMinutes: Int = 15) async throws -> [GoogleCalendarEvent] {
        let timeMin = date.addingTimeInterval(-Double(windowMinutes) * 60)
        let timeMax = date.addingTimeInterval(Double(windowMinutes) * 60)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "\(Self.baseURL)/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: timeMin)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "10"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleCalendarError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw GoogleCalendarError.unauthorized
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GoogleCalendarError.httpError(httpResponse.statusCode, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }

        return items.compactMap { parseEvent($0, formatter: formatter) }
    }

    private func parseEvent(_ json: [String: Any], formatter: ISO8601DateFormatter) -> GoogleCalendarEvent? {
        guard let id = json["id"] as? String,
              let summary = json["summary"] as? String else {
            return nil
        }

        // Parse start/end — can be dateTime or date (all-day events)
        guard let startObj = json["start"] as? [String: Any],
              let endObj = json["end"] as? [String: Any] else {
            return nil
        }

        let start: Date
        let end: Date

        if let startStr = startObj["dateTime"] as? String, let s = formatter.date(from: startStr) {
            start = s
        } else {
            return nil // Skip all-day events
        }

        if let endStr = endObj["dateTime"] as? String, let e = formatter.date(from: endStr) {
            end = e
        } else {
            return nil
        }

        // Parse attendees
        let attendees: [GoogleCalendarAttendee]
        if let attendeeList = json["attendees"] as? [[String: Any]] {
            attendees = attendeeList.compactMap { att in
                guard let email = att["email"] as? String else { return nil }
                return GoogleCalendarAttendee(
                    email: email,
                    displayName: att["displayName"] as? String,
                    isSelf: att["self"] as? Bool ?? false
                )
            }
        } else {
            attendees = []
        }

        return GoogleCalendarEvent(
            id: id,
            summary: summary,
            start: start,
            end: end,
            attendees: attendees
        )
    }
}
