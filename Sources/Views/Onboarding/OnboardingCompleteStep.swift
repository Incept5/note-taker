import SwiftUI

struct OnboardingCompleteStep: View {
    let screenRecordingGranted: Bool
    let microphoneGranted: Bool
    let hasWhisperModel: Bool
    let hasOllamaModel: Bool
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're All Set!")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                statusRow("Screen Recording", granted: screenRecordingGranted)
                statusRow("Microphone", granted: microphoneGranted)
                statusRow("Transcription Model", granted: hasWhisperModel)
                statusRow("Summarization (Ollama)", granted: hasOllamaModel, optional: true)
            }
            .padding()
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)

            Spacer()

            Button("Start Using NoteTaker") {
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 16)
        }
        .padding()
    }

    private func statusRow(_ label: String, granted: Bool, optional: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : (optional ? "minus.circle" : "exclamationmark.circle"))
                .foregroundStyle(granted ? .green : (optional ? .secondary : .orange))
                .font(.subheadline)

            Text(label)
                .font(.subheadline)

            if !granted && optional {
                Text("(skipped)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
