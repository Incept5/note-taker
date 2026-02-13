import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var modelManager: ModelManager
    let onDismiss: () -> Void
    var onModelReady: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Transcription Models")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(modelManager.models) { model in
                        modelRow(model)
                    }
                }
                .padding(.horizontal)
            }

            if modelManager.selectedModelName != nil {
                Text("Selected: \(modelManager.selectedModel?.displayName ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func modelRow(_ model: WhisperModel) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(model.displayName)
                        .font(.body.bold())
                    if model.id == modelManager.selectedModelName {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.sizeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if model.isDownloaded {
                if model.id == modelManager.selectedModelName {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Select") {
                        modelManager.selectModel(model.id)
                        onModelReady?()
                    }
                    .controlSize(.small)
                }
            } else if modelManager.downloadingModelId == model.id {
                VStack(spacing: 2) {
                    ProgressView(value: modelManager.downloadProgress)
                        .frame(width: 60)
                    Text("\(Int(modelManager.downloadProgress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
                    Task {
                        do {
                            try await modelManager.downloadModel(model.id)
                            onModelReady?()
                        } catch {
                            // Error is visible via downloadProgress reset
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            model.id == modelManager.selectedModelName
                ? Color.accentColor.opacity(0.1)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
    }
}
