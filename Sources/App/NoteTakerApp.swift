import SwiftUI
import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState = AppState()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar status item
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: "NoteTaker")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 320, height: 500)
        pop.behavior = .transient
        let hostingController = NSHostingController(
            rootView: MenuBarPopover(appState: appState)
        )
        // Let the popover resize to fit SwiftUI content
        hostingController.sizingOptions = [.preferredContentSize]
        pop.contentViewController = hostingController

        self.statusItem = item
        self.popover = pop
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Reset to idle when reopening after a completed workflow
            resetIfTerminalState()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Reset app state if we're in a terminal phase (work is done, nothing in progress).
    private func resetIfTerminalState() {
        switch appState.phase {
        case .summarized, .transcribed, .error, .stopped:
            appState.reset()
        default:
            // For idle, recording, transcribing, summarizing — keep current state
            appState.showingModelPicker = false
            appState.navigation = .none
        }
    }
}
