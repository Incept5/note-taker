import Foundation
import AppKit
import AudioToolbox
import Combine
import OSLog

final class AudioProcessDiscovery: ObservableObject {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "AudioProcessDiscovery")

    @Published private(set) var processes: [AudioProcess] = []

    private var cancellable: AnyCancellable?

    func discoverAudioProcesses() -> [AudioProcess] {
        do {
            let objectIDs = try AudioObjectID.readProcessList()
            let runningApps = NSWorkspace.shared.runningApplications

            let discovered: [AudioProcess] = objectIDs.compactMap { objectID in
                buildProcess(objectID: objectID, runningApps: runningApps)
            }

            return discovered.sorted { lhs, rhs in
                // Meeting apps first
                if lhs.isMeetingApp != rhs.isMeetingApp {
                    return lhs.isMeetingApp
                }
                // Audio-active next
                if lhs.audioActive != rhs.audioActive {
                    return lhs.audioActive
                }
                // Alphabetical
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } catch {
            logger.error("Failed to discover audio processes: \(error, privacy: .public)")
            return []
        }
    }

    func startMonitoring() {
        // Refresh immediately
        processes = discoverAudioProcesses()

        // Monitor workspace app changes
        cancellable = NSWorkspace.shared.publisher(for: \.runningApplications)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.processes = self?.discoverAudioProcesses() ?? []
            }
    }

    func stopMonitoring() {
        cancellable?.cancel()
        cancellable = nil
    }

    func refresh() {
        processes = discoverAudioProcesses()
    }

    private func buildProcess(objectID: AudioObjectID, runningApps: [NSRunningApplication]) -> AudioProcess? {
        do {
            let pid: pid_t = try objectID.readProcessPID()
            let bundleID = objectID.readProcessBundleID()
            let isRunning = objectID.readProcessIsRunning()

            // Try to match with a running application for richer metadata
            if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
                let name = app.localizedName
                    ?? app.bundleURL?.deletingPathExtension().lastPathComponent
                    ?? bundleID?.components(separatedBy: ".").last
                    ?? "Unknown (\(pid))"

                return AudioProcess(
                    id: pid,
                    kind: .app,
                    name: name,
                    audioActive: isRunning,
                    bundleID: app.bundleIdentifier ?? bundleID,
                    bundleURL: app.bundleURL,
                    objectID: objectID
                )
            }

            // Fallback for non-app processes
            let name = bundleID?.components(separatedBy: ".").last ?? "Process \(pid)"

            return AudioProcess(
                id: pid,
                kind: .process,
                name: name,
                audioActive: isRunning,
                bundleID: bundleID,
                bundleURL: nil,
                objectID: objectID
            )
        } catch {
            logger.warning("Failed to build process from objectID \(objectID, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}
