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
                self?.hide()
                onNewRecording()
            },
            onClose: { [weak self] in
                self?.hide()
            }
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Meeting Summary"
        win.animationBehavior = .none
        win.isRestorable = false
        win.contentViewController = NSHostingController(rootView: content)
        win.minSize = NSSize(width: 700, height: 400)
        win.delegate = self
        win.center()

        self.window = win

        // Show in Dock while result window is open so user can Cmd+Tab to it
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        hide()
    }

    /// Hide the window instead of closing it. This avoids tearing down the
    /// NSHostingView, which can crash if the autorelease pool was corrupted
    /// by layout recursion during SwiftUI re-renders.
    private func hide() {
        window?.orderOut(nil)
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - NSWindowDelegate

    /// Intercept the close button — hide instead of close to avoid teardown crash.
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            hide()
        }
        return false
    }
}
