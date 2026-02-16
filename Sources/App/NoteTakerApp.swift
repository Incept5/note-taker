import SwiftUI
import AppKit
import Combine

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState = AppState()
    private let resultWindowController = ResultWindowController()
    private lazy var settingsWindowController = SettingsWindowController(appState: appState)
    private var cancellables = Set<AnyCancellable>()

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

        // Auto-open result window when summarization completes
        appState.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self else { return }
                if case .summarized(let audio, let transcription, let summary) = phase {
                    self.showResultWindow(
                        summary: summary,
                        transcript: transcription.combinedText,
                        duration: audio.formattedDuration
                    )
                }
            }
            .store(in: &cancellables)

        // Bridge for history → result window
        appState.onShowResultWindow = { [weak self] summary, transcript, duration in
            self?.showResultWindow(summary: summary, transcript: transcript, duration: duration)
        }

        // Open settings in a proper window
        appState.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.popover?.performClose(nil)
            // Delay to let the popover fully dismiss — closing a popover deactivates
            // the app, which can prevent the new window from appearing in front.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.settingsWindowController.show()
            }
        }

        // Auto-show popover on first launch for onboarding
        if appState.showingOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showPopover()
        return true
    }

    @objc private func togglePopover() {
        guard let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let popover, let button = statusItem?.button else { return }
        resetIfTerminalState()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func showResultWindow(summary: MeetingSummary, transcript: String, duration: String) {
        popover?.performClose(nil)
        resultWindowController.show(
            summary: summary,
            transcript: transcript,
            duration: duration,
            onNewRecording: { [weak self] in
                self?.appState.reset()
            }
        )
    }

    /// Reset app state if we're in a terminal phase (work is done, nothing in progress).
    private func resetIfTerminalState() {
        guard !appState.showingOnboarding else { return }

        switch appState.phase {
        case .summarized, .transcribed, .error, .stopped:
            resultWindowController.close()
            appState.reset()
        default:
            // For idle, recording, transcribing, summarizing — keep current state
            appState.showingModelPicker = false
            appState.navigation = .none
        }
    }
}
