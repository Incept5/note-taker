import SwiftUI
import Combine

/// Centralized app state tying together process discovery, audio capture, and UI phase.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case stopped(CapturedAudio)
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): true
            case (.recording(let a), .recording(let b)): a == b
            case (.stopped(let a), .stopped(let b)): a.directory == b.directory
            case (.error(let a), .error(let b)): a == b
            default: false
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var selectedProcess: AudioProcess?

    let discovery = AudioProcessDiscovery()
    let captureService = AudioCaptureService()

    func startRecording() {
        guard let process = selectedProcess else { return }

        do {
            try captureService.startCapture(process: process)
            phase = .recording(since: Date())
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func stopRecording() {
        if let result = captureService.stopCapture() {
            phase = .stopped(result)
        } else {
            phase = .idle
        }
    }

    func reset() {
        phase = .idle
        selectedProcess = nil
    }
}
