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
            mlxModelManager: appState.mlxModelManager,
            onDismiss: { [weak self] in
                self?.hide()
            },
            onModelReady: { [weak self] in
                self?.hide()
                if case .stopped(let audio) = self?.appState.phase {
                    self?.appState.startTranscription(audio: audio)
                }
            }
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "NoteTaker Settings"
        win.animationBehavior = .none
        win.isRestorable = false
        win.minSize = NSSize(width: 400, height: 350)
        win.delegate = self

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        win.contentView = hostingView

        win.setContentSize(NSSize(width: 500, height: 550))
        win.center()

        self.window = win

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        hide()
    }

    /// Hide the window instead of closing it. This avoids tearing down the
    /// NSHostingView, which can freeze the app if the autorelease pool was
    /// corrupted by layout recursion during SwiftUI re-renders.
    private func hide() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - NSWindowDelegate

    /// Intercept the close button — hide instead of close to avoid teardown.
    nonisolated func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            hide()
        }
        return false
    }
}
