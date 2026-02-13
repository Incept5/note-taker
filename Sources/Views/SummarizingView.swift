import SwiftUI

struct SummarizingView: View {
    @ObservedObject var summarizationService: SummarizationService

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)

            Text("Summarizing...")
                .font(.headline)

            if let model = summarizationService.selectedModel {
                Text("Using \(model)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: summarizationService.progress)
                .progressViewStyle(.linear)
                .padding(.horizontal)

            if !summarizationService.progressText.isEmpty {
                Text(summarizationService.progressText)
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
