import Foundation
import WhisperKit

@MainActor
final class TranscriptionService: ObservableObject {
    @Published var progress: Double = 0
    @Published var progressText: String = ""

    private var whisperKit: WhisperKit?
    private var loadedModel: String?
    private let modelManager: ModelManager

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func transcribe(audio: CapturedAudio) async throws -> MeetingTranscription {
        let start = Date()

        guard let model = modelManager.selectedModel else {
            throw TranscriptionError.noModelSelected
        }

        guard model.isDownloaded else {
            throw TranscriptionError.modelNotDownloaded(model.id)
        }

        try await loadWhisperKit(model: model.id)

        guard let pipe = whisperKit else {
            throw TranscriptionError.modelLoadFailed("WhisperKit failed to initialize")
        }

        let options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            wordTimestamps: true
        )

        // Transcribe system audio
        progress = 0
        progressText = "Transcribing system audio..."

        guard FileManager.default.fileExists(atPath: audio.systemAudioURL.path) else {
            throw TranscriptionError.audioFileNotFound(audio.systemAudioURL)
        }

        let systemTranscript = try await transcribeFile(
            pipe: pipe,
            path: audio.systemAudioURL.path,
            options: options,
            label: "Others"
        )

        progress = 0.5

        // Transcribe mic audio if available
        var micTranscript: TimestampedTranscript? = nil

        if FileManager.default.fileExists(atPath: audio.microphoneURL.path) {
            progressText = "Transcribing microphone audio..."

            let transcript = try await transcribeFile(
                pipe: pipe,
                path: audio.microphoneURL.path,
                options: options,
                label: "You"
            )

            if !transcript.fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                micTranscript = transcript
            }
        }

        progress = 1.0
        progressText = "Done"

        // Build combined text with speaker labels
        var combined = ""
        let systemText = systemTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !systemText.isEmpty {
            combined += "Others:\n\(systemTranscript.fullText)\n"
        }
        if let mic = micTranscript {
            if !combined.isEmpty { combined += "\n" }
            combined += "You:\n\(mic.fullText)\n"
        }
        if combined.isEmpty {
            combined = systemTranscript.fullText
        }

        let duration = Date().timeIntervalSince(start)

        return MeetingTranscription(
            systemTranscript: systemTranscript,
            micTranscript: micTranscript,
            combinedText: combined,
            processingDuration: duration,
            modelUsed: model.displayName
        )
    }

    private func transcribeFile(
        pipe: WhisperKit,
        path: String,
        options: DecodingOptions,
        label: String
    ) async throws -> TimestampedTranscript {
        let results = try await pipe.transcribe(
            audioPath: path,
            decodeOptions: options
        ) { [weak self] progressInfo in
            Task { @MainActor in
                if !progressInfo.text.isEmpty {
                    self?.progressText = "\(label): \(String(progressInfo.text.suffix(80)))"
                }
            }
            return nil // continue transcription
        }

        // Extract segments and text from WhisperKit results
        var segments: [TranscriptSegment] = []
        var fullText = ""

        for result in results {
            for segment in result.segments {
                segments.append(TranscriptSegment(
                    text: segment.text,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end)
                ))
            }
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                if !fullText.isEmpty { fullText += " " }
                fullText += text
            }
        }

        return TimestampedTranscript(segments: segments, fullText: fullText)
    }

    private func loadWhisperKit(model: String) async throws {
        if loadedModel == model, whisperKit != nil { return }

        progressText = "Loading model..."

        let config = WhisperKitConfig(
            model: model,
            verbose: false,
            logLevel: .none
        )

        do {
            whisperKit = try await WhisperKit(config)
            loadedModel = model
        } catch {
            whisperKit = nil
            loadedModel = nil
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }
}
