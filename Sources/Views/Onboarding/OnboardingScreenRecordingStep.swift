import SwiftUI
import ScreenCaptureKit

struct OnboardingScreenRecordingStep: View {
    @Binding var isGranted: Bool
    let onContinue: () -> Void

    @State private var checking = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Screen Recording Permission")
                .font(.headline)

            Text("NoteTaker uses this to capture system audio from apps like Zoom and Teams. It does **not** record your screen — only audio.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if isGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.bold())
            } else {
                VStack(spacing: 10) {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Check Again") {
                        Task { await checkPermission() }
                    }
                    .controlSize(.small)
                }

                Text("After granting permission, fully quit and relaunch NoteTaker.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 16)
        }
        .padding()
        .task {
            await checkPermission()
        }
    }

    private func checkPermission() async {
        checking = true
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            isGranted = true
        } catch {
            isGranted = false
        }
        checking = false
    }
}
