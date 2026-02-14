import SwiftUI
import AVFoundation

struct OnboardingMicrophoneStep: View {
    @Binding var isGranted: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "mic.circle")
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Microphone Access")
                .font(.headline)

            Text("NoteTaker needs microphone access to capture your voice during meetings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if isGranted {
                Label("Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.bold())
            } else {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)

                if status == .denied || status == .restricted {
                    VStack(spacing: 10) {
                        Label("Permission Denied", systemImage: "xmark.circle")
                            .foregroundStyle(.orange)
                            .font(.subheadline)

                        Button("Open System Settings") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                            )
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button("Grant Access") {
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                            Task { @MainActor in
                                isGranted = granted
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
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
        .onAppear {
            checkStatus()
        }
    }

    private func checkStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        isGranted = (status == .authorized)
    }
}
