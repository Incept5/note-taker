import SwiftUI

struct TranscriptionResultView: View {
    let audio: CapturedAudio
    let result: MeetingTranscription
    let onNewRecording: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.document.fill")
                .font(.system(size: 32))
                .foregroundStyle(.blue)

            Text("Transcription Complete")
                .font(.headline)

            HStack(spacing: 16) {
                Label(audio.formattedDuration, systemImage: "clock")
                Label(result.modelUsed, systemImage: "cpu")
                Label(formatProcessingTime(result.processingDuration), systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let mic = result.micTranscript, !mic.fullText.isEmpty {
                        sectionHeader("Others")
                        Text(result.systemTranscript.fullText)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)

                        sectionHeader("You")
                        Text(mic.fullText)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                    } else {
                        Text(result.systemTranscript.fullText)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)

            Divider()

            HStack(spacing: 12) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.combinedText, forType: .string)
                }

                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: audio.directory.path)
                }

                Button("New Recording") {
                    onNewRecording()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 12)
        }
        .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func formatProcessingTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }
}
