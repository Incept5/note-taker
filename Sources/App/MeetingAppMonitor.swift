import AppKit
import OSLog

/// Monitors NSWorkspace for meeting app launches and terminations (Zoom, Teams).
/// Event-driven via NSWorkspace notifications — no polling.
@MainActor
final class MeetingAppMonitor {
    /// Bundle ID prefixes to watch for.
    private static let monitoredApps: [(bundlePrefix: String, displayName: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
    ]

    var onMeetingAppLaunched: ((@MainActor (String) -> Void))?
    var onMeetingAppTerminated: ((@MainActor (String) -> Void))?

    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "MeetingAppMonitor")

    func start() {
        let center = NSWorkspace.shared.notificationCenter

        // Capture callbacks as local vars to avoid referencing self in nonisolated closures
        let launchCallback = onMeetingAppLaunched
        let terminateCallback = onMeetingAppTerminated

        launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  let match = MeetingAppMonitor.matchingApp(bundleId: bundleId) else { return }
            Task { @MainActor in
                Logger(subsystem: "com.incept5.NoteTaker", category: "MeetingAppMonitor")
                    .info("Meeting app launched: \(match, privacy: .public)")
                launchCallback?(match)
            }
        }

        terminateObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  let match = MeetingAppMonitor.matchingApp(bundleId: bundleId) else { return }
            Task { @MainActor in
                Logger(subsystem: "com.incept5.NoteTaker", category: "MeetingAppMonitor")
                    .info("Meeting app terminated: \(match, privacy: .public)")
                terminateCallback?(match)
            }
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let obs = launchObserver { center.removeObserver(obs) }
        if let obs = terminateObserver { center.removeObserver(obs) }
        launchObserver = nil
        terminateObserver = nil
    }

    /// Returns the display name if the bundle ID matches a monitored app, nil otherwise.
    nonisolated private static func matchingApp(bundleId: String) -> String? {
        for app in monitoredApps {
            if bundleId.hasPrefix(app.bundlePrefix) {
                return app.displayName
            }
        }
        return nil
    }
}
