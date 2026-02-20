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

        // WhisperKit auto-downloads if the model isn't cached locally
        try await loadWhisperKit(model: model.id)

        guard let pipe = whisperKit else {
            throw TranscriptionError.modelLoadFailed("WhisperKit failed to initialize")
        }

        let options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            wordTimestamps: true
        )

        // Transcribe system audio (captures all meeting participants)
        progress = 0
        progressText = "Transcribing system audio..."

        guard FileManager.default.fileExists(atPath: audio.systemAudioURL.path) else {
            throw TranscriptionError.audioFileNotFound(audio.systemAudioURL)
        }

        let systemTranscript = try await transcribeFile(
            pipe: pipe,
            path: audio.systemAudioURL.path,
            options: options,
            label: "System"
        )

        progress = 1.0
        progressText = "Done"

        let duration = Date().timeIntervalSince(start)

        return MeetingTranscription(
            systemTranscript: systemTranscript,
            micTranscript: nil,
            combinedText: systemTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
            processingDuration: duration,
            modelUsed: model.displayName
        )
    }

    /// Build a MeetingTranscription using pre-existing streaming segments for system audio.
    func transcribeWithStreamingSegments(
        audio: CapturedAudio,
        systemTranscript: TimestampedTranscript
    ) async throws -> MeetingTranscription {
        let start = Date()

        guard let model = modelManager.selectedModel else {
            throw TranscriptionError.noModelSelected
        }

        progress = 1.0
        progressText = "Done"

        let duration = Date().timeIntervalSince(start)

        return MeetingTranscription(
            systemTranscript: systemTranscript,
            micTranscript: nil,
            combinedText: systemTranscript.fullText.trimmingCharacters(in: .whitespacesAndNewlines),
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

        // Extract segments and text from WhisperKit results, stripping
        // raw Whisper tokens like <|startoftranscript|>, <|en|>, <|0.00|>, etc.
        var segments: [TranscriptSegment] = []
        var fullText = ""

        for result in results {
            for segment in result.segments {
                let cleaned = Self.stripWhisperTokens(segment.text)
                if cleaned.isEmpty { continue }
                segments.append(TranscriptSegment(
                    text: cleaned,
                    startTime: TimeInterval(segment.start),
                    endTime: TimeInterval(segment.end)
                ))
            }
            let text = Self.stripWhisperTokens(result.text)
            if !text.isEmpty {
                if !fullText.isEmpty { fullText += " " }
                fullText += text
            }
        }

        return TimestampedTranscript(segments: segments, fullText: fullText)
    }

    /// Remove raw Whisper special tokens from text (e.g. `<|startoftranscript|>`, `<|en|>`, `<|0.00|>`).
    private static func stripWhisperTokens(_ text: String) -> String {
        // Match all <|...|> tokens
        let stripped = text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )
        // Collapse multiple spaces and trim
        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadWhisperKit(model: String) async throws {
        if loadedModel == model, whisperKit != nil { return }

        progressText = "Downloading model (first time only)..."

        // Download the model first (no-op if already cached)
        let modelURL: URL
        do {
            modelURL = try await WhisperKit.download(
                variant: model,
                useBackgroundSession: false,
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        let pct = Int(progress.fractionCompleted * 100)
                        self?.progressText = "Downloading model... \(pct)%"
                    }
                }
            )
        } catch {
            throw TranscriptionError.modelLoadFailed("Failed to download model '\(model)': \(error.localizedDescription)")
        }

        progressText = "Loading model..."

        let config = WhisperKitConfig(
            modelFolder: modelURL.path,
            verbose: false,
            logLevel: .none,
            load: true,
            download: false
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
