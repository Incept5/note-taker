import AVFoundation
import OSLog
import WhisperKit

/// Thread-safe audio sample accumulator. Called from the audio queue,
/// read from the main actor for transcription.
final class AudioSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        lock.lock()
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func snapshot(lastNSamples: Int? = nil) -> (samples: [Float], totalCount: Int) {
        lock.lock()
        let total = samples.count
        let result: [Float]
        if let n = lastNSamples, n < total {
            result = Array(samples[(total - n)...])
        } else {
            result = samples
        }
        lock.unlock()
        return (result, total)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return samples.count
    }
}

/// Receives 48kHz stereo audio buffers during recording, converts to 16kHz mono,
/// and periodically transcribes the accumulated audio using WhisperKit.
/// Publishes transcript segments in near real-time.
@MainActor
final class StreamingTranscriber {
    private let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "StreamingTranscriber")

    /// All confirmed + tentative segments so far.
    private(set) var segments: [TranscriptSegment] = []

    /// Called on the main actor when segments update.
    var onSegmentsUpdated: (([TranscriptSegment]) -> Void)?

    private let modelManager: ModelManager
    private var whisperKit: WhisperKit?

    // Thread-safe audio accumulation
    private let accumulator = AudioSampleAccumulator()
    private let targetSampleRate: Double = 16000

    // Scheduling
    private var isTranscribing = false
    private var chunkTimer: Task<Void, Never>?
    private let chunkIntervalSeconds: Double = 10
    private let windowDurationSeconds: Double = 30

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Load the WhisperKit model so it's ready for streaming chunks.
    func loadModel() async throws {
        guard let model = modelManager.selectedModel else {
            throw TranscriptionError.noModelSelected
        }

        let modelURL = try await WhisperKit.download(
            variant: model.id,
            useBackgroundSession: false,
            from: "argmaxinc/whisperkit-coreml",
            progressCallback: nil
        )

        let config = WhisperKitConfig(
            modelFolder: modelURL.path,
            verbose: false,
            logLevel: .none,
            load: true,
            download: false
        )

        whisperKit = try await WhisperKit(config)
        logger.info("WhisperKit loaded for streaming: \(model.id)")
    }

    /// Start the periodic transcription timer.
    func start() {
        logger.info("Streaming transcription started")
        chunkTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.chunkIntervalSeconds ?? 10))
                guard !Task.isCancelled else { break }
                await self?.transcribeCurrentWindow()
            }
        }
    }

    /// Stop streaming and cancel any in-flight transcription.
    func stop() {
        logger.info("Streaming transcription stopped")
        chunkTimer?.cancel()
        chunkTimer = nil
    }

    /// Called from the audio queue with 48kHz stereo float32 buffers.
    /// Thread-safe — converts and appends to the accumulator.
    nonisolated func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        guard buffer.format.commonFormat == .pcmFormatFloat32 else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let channelCount = Int(buffer.format.channelCount)

        // Convert to mono
        var monoSamples: [Float]

        if buffer.format.isInterleaved {
            guard let data = buffer.floatChannelData?[0] else { return }
            monoSamples = [Float](repeating: 0, count: frameCount)
            if channelCount >= 2 {
                for i in 0..<frameCount {
                    monoSamples[i] = (data[i * channelCount] + data[i * channelCount + 1]) * 0.5
                }
            } else {
                for i in 0..<frameCount {
                    monoSamples[i] = data[i]
                }
            }
        } else {
            // Non-interleaved (ScreenCaptureKit default)
            guard let channelData = buffer.floatChannelData else { return }
            if channelCount >= 2 {
                let ch0 = channelData[0]
                let ch1 = channelData[1]
                monoSamples = [Float](repeating: 0, count: frameCount)
                for i in 0..<frameCount {
                    monoSamples[i] = (ch0[i] + ch1[i]) * 0.5
                }
            } else {
                monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
            }
        }

        // Downsample from 48kHz to 16kHz (take every 3rd sample)
        let ratio = Int(buffer.format.sampleRate / targetSampleRate)
        guard ratio > 0 else { return }

        let downsampled: [Float]
        if ratio == 1 {
            downsampled = monoSamples
        } else {
            let outputCount = monoSamples.count / ratio
            var ds = [Float](repeating: 0, count: outputCount)
            for i in 0..<outputCount {
                ds[i] = monoSamples[i * ratio]
            }
            downsampled = ds
        }

        accumulator.append(downsampled)
    }

    /// Transcribe the trailing window of accumulated audio.
    private func transcribeCurrentWindow() async {
        guard !isTranscribing else { return }
        guard let pipe = whisperKit else { return }

        let windowSamples = Int(windowDurationSeconds * targetSampleRate)
        let snapshot = accumulator.snapshot(lastNSamples: windowSamples)

        guard snapshot.totalCount > Int(targetSampleRate) else { return } // need at least 1s

        let audioChunk = snapshot.samples
        let startIdx = snapshot.totalCount - audioChunk.count
        let chunkStartTime = Double(startIdx) / targetSampleRate

        isTranscribing = true
        defer { isTranscribing = false }

        let options = DecodingOptions(
            language: "en",
            temperature: 0.0,
            wordTimestamps: true
        )

        do {
            let results = try await pipe.transcribe(
                audioArray: audioChunk,
                decodeOptions: options
            )

            var newSegments: [TranscriptSegment] = []
            for result in results {
                for segment in result.segments {
                    let cleaned = Self.stripWhisperTokens(segment.text)
                    if cleaned.isEmpty { continue }
                    newSegments.append(TranscriptSegment(
                        text: cleaned,
                        startTime: chunkStartTime + TimeInterval(segment.start),
                        endTime: chunkStartTime + TimeInterval(segment.end)
                    ))
                }
            }

            let merged = mergeSegments(existing: segments, incoming: newSegments)
            segments = merged
            onSegmentsUpdated?(merged)

        } catch {
            logger.error("Streaming transcription chunk failed: \(error, privacy: .public)")
        }
    }

    /// Merge incoming segments with existing ones, deduplicating overlaps.
    private func mergeSegments(
        existing: [TranscriptSegment],
        incoming: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        guard !existing.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return existing }

        var result: [TranscriptSegment] = []

        // Keep existing segments that start before the incoming window
        let incomingWindowStart = incoming.first?.startTime ?? 0
        let tolerance: TimeInterval = 1.0
        for seg in existing {
            if seg.startTime < incomingWindowStart - tolerance {
                result.append(seg)
            }
        }

        // Append all incoming segments (they replace overlapping existing ones)
        result.append(contentsOf: incoming)
        result.sort { $0.startTime < $1.startTime }

        return result
    }

    /// Build the full text from all accumulated segments.
    var fullText: String {
        segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Build a TimestampedTranscript from the streaming results.
    var timestampedTranscript: TimestampedTranscript {
        TimestampedTranscript(segments: segments, fullText: fullText)
    }

    private static func stripWhisperTokens(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
