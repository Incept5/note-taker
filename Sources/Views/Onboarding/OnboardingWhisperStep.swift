import SwiftUI

struct OnboardingWhisperStep: View {
    @ObservedObject var modelManager: ModelManager
    let onContinue: () -> Void

    @State private var downloadError: String?
    @State private var downloadingId: String?
    @State private var downloadProgress: Double = 0

    private var recommendedModels: [WhisperModel] {
        modelManager.models.filter { $0.id == "large-v3" || $0.id == "base" }
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(.purple)

            Text("Download a Transcription Model")
                .font(.headline)

            Text("WhisperKit runs entirely on your Mac. Choose a model to get started:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(recommendedModels) { model in
                    modelRow(model)
                }
            }

            if let error = downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!modelManager.hasDownloadedModel)
            .padding(.bottom, 4)

            if !modelManager.hasDownloadedModel {
                Text("Download at least one model to continue.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 12)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func modelRow(_ model: WhisperModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.displayName)
                        .font(.body.bold())
                    if model.id == "large-v3" {
                        Text("Recommended")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple, in: Capsule())
                    }
                }
                Text("\(model.description) (\(model.sizeLabel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if downloadingId == model.id {
                VStack(spacing: 2) {
                    ProgressView(value: downloadProgress)
                        .frame(width: 60)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
                    downloadError = nil
                    downloadingId = model.id
                    downloadProgress = 0
                    modelManager.downloadModelDetached(
                        model.id,
                        onProgress: { fraction in
                            DispatchQueue.main.async {
                                downloadProgress = fraction
                            }
                        },
                        onComplete: { success in
                            DispatchQueue.main.async {
                                if success {
                                    modelManager.markModelDownloaded(model.id)
                                }
                                downloadingId = nil
                                if !success {
                                    downloadError = "Download failed. Please try again."
                                }
                            }
                        }
                    )
                }
                .controlSize(.small)
                .disabled(downloadingId != nil)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            model.isDownloaded ? Color.green.opacity(0.08) : Color.secondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
