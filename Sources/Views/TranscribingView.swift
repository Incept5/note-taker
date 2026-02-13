import SwiftUI

struct TranscribingView: View {
    @ObservedObject var transcriptionService: TranscriptionService
    let progress: Double

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("Transcribing...")
                .font(.headline)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .padding(.horizontal)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !transcriptionService.progressText.isEmpty {
                Text(transcriptionService.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}
