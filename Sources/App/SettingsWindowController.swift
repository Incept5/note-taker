import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        // If already showing, bring to front
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = ModelPickerView(
            modelManager: appState.modelManager,
            appState: appState,
            onDismiss: { [weak self] in
                self?.close()
            },
            onModelReady: { [weak self] in
                self?.close()
                if case .stopped(let audio) = self?.appState.phase {
                    self?.appState.startTranscription(audio: audio)
                }
            }
        )

        let hostingController = NSHostingController(rootView: content)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "NoteTaker Settings"
        win.contentViewController = hostingController
        win.minSize = NSSize(width: 400, height: 350)
        win.setFrameAutosaveName("NoteTakerSettingsWindow")
        win.delegate = self
        win.center()

        self.window = win

        // Show in Dock while settings window is open so user can Cmd+Tab to it
        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
