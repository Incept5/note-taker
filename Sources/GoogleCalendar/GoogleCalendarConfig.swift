import Foundation

enum GoogleCalendarConfig {
    static let clientId = "41323228832-tu9igm8r3so8c24hvtv81jf0lklr15he.apps.googleusercontent.com"
    static let clientSecret = "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"

    static var isConfigured: Bool {
        !clientId.starts(with: "YOUR_")
    }
}
