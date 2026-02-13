import SwiftUI
import Combine

/// Centralized app state tying together process discovery, audio capture, and UI phase.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case stopped(CapturedAudio)
        case transcribing(CapturedAudio, progress: Double)
        case transcribed(CapturedAudio, MeetingTranscription)
        case summarizing(CapturedAudio, MeetingTranscription)
        case summarized(CapturedAudio, MeetingTranscription, MeetingSummary)
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): true
            case (.recording(let a), .recording(let b)): a == b
            case (.stopped(let a), .stopped(let b)): a.directory == b.directory
            case (.transcribing(let a, _), .transcribing(let b, _)): a.directory == b.directory
            case (.transcribed(let a, _), .transcribed(let b, _)): a.directory == b.directory
            case (.summarizing(let a, _), .summarizing(let b, _)): a.directory == b.directory
            case (.summarized(let a, _, _), .summarized(let b, _, _)): a.directory == b.directory
            case (.error(let a), .error(let b)): a == b
            default: false
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var selectedProcess: AudioProcess?
    @Published var showingModelPicker = false
    @Published var selectedOllamaModel: String?

    let discovery = AudioProcessDiscovery()
    let captureService = AudioCaptureService()
    let modelManager: ModelManager
    let transcriptionService: TranscriptionService
    let summarizationService = SummarizationService()

    init() {
        let mm = ModelManager()
        modelManager = mm
        transcriptionService = TranscriptionService(modelManager: mm)
    }

    func startRecording() {
        guard let process = selectedProcess else { return }

        do {
            try captureService.startCapture(process: process)
            phase = .recording(since: Date())
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    func stopRecording() {
        if let result = captureService.stopCapture() {
            phase = .stopped(result)
            // Auto-start transcription if a model is ready
            if modelManager.selectedModel?.isDownloaded == true {
                startTranscription(audio: result)
            }
        } else {
            phase = .idle
        }
    }

    func startTranscription(audio: CapturedAudio) {
        phase = .transcribing(audio, progress: 0)

        Task {
            // Observe progress from transcription service
            let progressTask = Task {
                for await _ in transcriptionService.$progress.values {
                    if case .transcribing(let a, _) = phase {
                        phase = .transcribing(a, progress: transcriptionService.progress)
                    }
                }
            }

            do {
                let result = try await transcriptionService.transcribe(audio: audio)
                progressTask.cancel()
                phase = .transcribed(audio, result)
            } catch {
                progressTask.cancel()
                phase = .error(error.localizedDescription)
            }
        }
    }

    func startSummarization(audio: CapturedAudio, transcription: MeetingTranscription) {
        guard let model = selectedOllamaModel else {
            phase = .error(SummarizationError.noModelSelected.localizedDescription)
            return
        }

        phase = .summarizing(audio, transcription)
        summarizationService.selectedModel = model

        Task {
            do {
                let summary = try await summarizationService.summarize(
                    transcript: transcription.combinedText,
                    appName: selectedProcess?.name,
                    duration: audio.duration
                )
                phase = .summarized(audio, transcription, summary)
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    func reset() {
        phase = .idle
        selectedProcess = nil
        showingModelPicker = false
    }
}
