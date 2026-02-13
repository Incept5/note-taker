import AppKit
import SwiftUI

@MainActor
final class ResultWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    var isOpen: Bool { window != nil }

    func show(
        summary: MeetingSummary,
        transcript: String,
        duration: String,
        onNewRecording: @escaping () -> Void
    ) {
        // If already showing, bring to front
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = MeetingResultWindowContent(
            summary: summary,
            transcript: transcript,
            duration: duration,
            onNewRecording: { [weak self] in
                self?.close()
                onNewRecording()
            },
            onClose: { [weak self] in
                self?.close()
            }
        )

        let hostingController = NSHostingController(rootView: content)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Meeting Summary"
        win.contentViewController = hostingController
        win.minSize = NSSize(width: 700, height: 400)
        win.setFrameAutosaveName("MeetingResultWindow")
        win.delegate = self
        win.center()

        self.window = win

        // Show in Dock while result window is open so user can Cmd+Tab to it
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        // windowWillClose handles cleanup
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
            // Revert to accessory (menu bar only, no Dock icon)
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
