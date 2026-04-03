import Foundation
import os

/// Multi-layer post-processing to remove hallucinated, repetitive, and garbage
/// segments from transcription output (both SFSpeech and WhisperKit).
///
/// Inspired by the whisper-guard approach in silverstein/minutes.
struct TranscriptPostProcessor {

    private static let logger = Logger(subsystem: "com.incept5.NoteTaker", category: "TranscriptPostProcessor")

    // MARK: - Public API

    /// Process a transcript, removing hallucinated segments and rebuilding full text.
    /// Returns the cleaned transcript and the number of segments removed.
    static func process(_ transcript: TimestampedTranscript) -> (cleaned: TimestampedTranscript, removedCount: Int) {
        let original = transcript.segments
        guard !original.isEmpty else {
            return (transcript, 0)
        }

        var segments = original

        // Apply filters in order — each operates on the output of the previous
        segments = removeConsecutiveRepetitions(segments)
        segments = removeInterleavedHallucinations(segments)
        segments = trimTrailingNoise(segments)
        segments = removeFillerOnlySegments(segments)

        let removedCount = original.count - segments.count
        if removedCount > 0 {
            logger.info("Post-processing removed \(removedCount) of \(original.count) segments")
        }

        let fullText = segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return (TimestampedTranscript(segments: segments, fullText: fullText), removedCount)
    }

    /// Process raw combined text (for paths where we only have a string, not segments).
    static func processText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return text }

        var result: [String] = []
        for line in lines {
            // Skip known hallucination phrases
            if isKnownHallucinationPhrase(line) { continue }

            // Skip filler-only lines
            let words = wordArray(line)
            if !words.isEmpty && fillerRatio(words) > 0.7 { continue }

            // Skip if duplicate of previous line
            if let prev = result.last, jaccardSimilarity(wordArray(prev), words) > 0.8 { continue }

            result.append(line)
        }

        return result.joined(separator: " ")
    }

    // MARK: - Filter 1: Consecutive Repetition Detection

    /// Drop segments that are >80% similar (word-level Jaccard) to the previous segment.
    private static func removeConsecutiveRepetitions(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard segments.count > 1 else { return segments }

        var result: [TranscriptSegment] = [segments[0]]

        for i in 1..<segments.count {
            let prevWords = wordArray(result.last!.text)
            let currWords = wordArray(segments[i].text)

            if jaccardSimilarity(prevWords, currWords) > 0.8 {
                logger.debug("Repetition filter: dropped segment \(i) — too similar to previous")
                continue
            }
            result.append(segments[i])
        }

        return result
    }

    // MARK: - Filter 2: Interleaved A/B Hallucination Detection

    /// Detect when a single phrase dominates a sliding window of segments.
    /// Whisper sometimes alternates between two hallucinated phrases.
    private static func removeInterleavedHallucinations(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let windowSize = 8
        guard segments.count >= windowSize else { return segments }

        // Find windows where a single phrase dominates
        var indicesToRemove = Set<Int>()

        for windowStart in 0...(segments.count - windowSize) {
            let windowEnd = windowStart + windowSize
            let windowSegments = Array(segments[windowStart..<windowEnd])

            // Extract all 4+ word phrases from the window
            let allPhrases = windowSegments.flatMap { extractPhrases(from: $0.text, minWords: 4) }

            // Count phrase occurrences
            var phraseCounts: [String: Int] = [:]
            for phrase in allPhrases {
                phraseCounts[phrase, default: 0] += 1
            }

            // Check if any phrase dominates
            guard let (dominantPhrase, count) = phraseCounts.max(by: { $0.value < $1.value }) else { continue }
            guard count >= 4 else { continue } // Need at least 4 occurrences in the window

            // Check what fraction of text in the window this phrase accounts for
            let totalWords = windowSegments.reduce(0) { $0 + wordArray($1.text).count }
            let phraseWords = dominantPhrase.split(separator: " ").count * count
            let dominance = Double(phraseWords) / Double(max(totalWords, 1))

            if dominance > 0.6 {
                logger.debug("A/B hallucination filter: phrase '\(dominantPhrase)' dominates window at \(windowStart) (\(String(format: "%.0f", dominance * 100))%)")
                // Keep only the first segment in the window, remove the rest
                for i in (windowStart + 1)..<windowEnd {
                    indicesToRemove.insert(i)
                }
            }
        }

        if indicesToRemove.isEmpty { return segments }

        return segments.enumerated()
            .filter { !indicesToRemove.contains($0.offset) }
            .map { $0.element }
    }

    // MARK: - Filter 3: Trailing Noise Trimming

    private static let knownHallucinationPhrases: Set<String> = [
        "thank you for watching",
        "thanks for watching",
        "please subscribe",
        "please like and subscribe",
        "see you next time",
        "see you in the next video",
        "subtitles by the amara.org community",
        "subtitles by",
        "music",
        "blank audio",
        "blank_audio",
        "silence",
        "applause",
        "laughter",
    ]

    /// Remove trailing segments that match known hallucination phrases or are single-word repetitions.
    private static func trimTrailingNoise(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        var result = segments

        while let last = result.last {
            let text = last.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if isKnownHallucinationPhrase(text) {
                logger.debug("Trailing noise filter: removed '\(text)'")
                result.removeLast()
                continue
            }

            // Check for single-word repetition (e.g., "you you you you")
            let words = wordArray(text)
            if words.count >= 3 {
                let uniqueWords = Set(words)
                if uniqueWords.count == 1 {
                    logger.debug("Trailing noise filter: removed repeated word '\(uniqueWords.first ?? "")'")
                    result.removeLast()
                    continue
                }
            }

            break // First non-noise segment — stop trimming
        }

        return result
    }

    private static func isKnownHallucinationPhrase(_ text: String) -> Bool {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Exact match
        if knownHallucinationPhrases.contains(normalized) { return true }

        // Substring match (e.g., "subtitles by the amara.org community" contains "subtitles by")
        for phrase in knownHallucinationPhrases {
            if normalized.hasPrefix(phrase) { return true }
        }

        return false
    }

    // MARK: - Filter 4: Filler-Only Segment Removal

    private static let fillerWords: Set<String> = [
        "um", "uh", "uhm", "uhh", "umm",
        "yeah", "yep", "yup",
        "ok", "okay",
        "like",
        "so",
        "right",
        "mhm", "hmm", "hm", "mm",
        "ah", "oh",
        "well",
        "you know",
    ]

    /// Remove segments where filler words constitute >70% of content.
    private static func removeFillerOnlySegments(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        return segments.filter { segment in
            let words = wordArray(segment.text)
            guard words.count >= 2 else { return true } // Keep very short segments (might be important single words)

            let ratio = fillerRatio(words)
            if ratio > 0.7 {
                logger.debug("Filler filter: removed segment with \(String(format: "%.0f", ratio * 100))% fillers")
                return false
            }
            return true
        }
    }

    // MARK: - Helpers

    /// Split text into lowercased word array.
    private static func wordArray(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
    }

    /// Word-level Jaccard similarity: |intersection| / |union|.
    private static func jaccardSimilarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty || !b.isEmpty else { return 1.0 }
        let setA = Set(a)
        let setB = Set(b)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(max(union, 1))
    }

    /// Ratio of filler words in a word array.
    private static func fillerRatio(_ words: [String]) -> Double {
        guard !words.isEmpty else { return 0 }
        let fillerCount = words.filter { fillerWords.contains($0) }.count
        return Double(fillerCount) / Double(words.count)
    }

    /// Extract all contiguous phrases of `minWords` or more from text.
    private static func extractPhrases(from text: String, minWords: Int) -> [String] {
        let words = wordArray(text)
        guard words.count >= minWords else { return [] }

        var phrases: [String] = []
        for length in minWords...min(words.count, 8) {
            for start in 0...(words.count - length) {
                let phrase = words[start..<(start + length)].joined(separator: " ")
                phrases.append(phrase)
            }
        }
        return phrases
    }
}
