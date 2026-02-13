import SwiftUI

struct ReadyView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Ready to Record")
                .font(.headline)

            Text("Captures all system audio and your microphone")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Start Recording") {
                appState.startRecording()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}
