import SwiftUI

struct OnboardingWelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Welcome to NoteTaker")
                .font(.headline)

            Text("Transcribe and summarize your meetings — entirely on your Mac. No audio ever leaves your machine.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Let's set up a few things first.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Get Started") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 16)
        }
        .padding()
    }
}
