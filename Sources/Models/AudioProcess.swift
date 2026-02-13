import Foundation
import AppKit
import AudioToolbox

struct AudioProcess: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case process
        case app
    }

    var id: pid_t
    var kind: Kind
    var name: String
    var audioActive: Bool
    var bundleID: String?
    var bundleURL: URL?
    var objectID: AudioObjectID

    var isMeetingApp: Bool {
        guard let bundleID else { return false }
        return Self.meetingAppBundleIDs.contains(bundleID)
    }

    static let meetingAppBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.google.Chrome",
        "com.cisco.webex.meetings",
        "com.gotomeeting.GoToMeeting",
        "com.ringcentral.ringcentral",
        "com.skype.skype",
        "com.discord.discord",
        "app.around.desktop",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.brave.Browser",
    ]
}

extension AudioProcess {
    @MainActor
    var icon: NSImage {
        guard let bundleURL else { return kind.defaultIcon }
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        image.size = NSSize(width: 32, height: 32)
        return image
    }
}

extension AudioProcess.Kind {
    @MainActor
    var defaultIcon: NSImage {
        switch self {
        case .process: NSWorkspace.shared.icon(for: .unixExecutable)
        case .app: NSWorkspace.shared.icon(for: .applicationBundle)
        }
    }
}
