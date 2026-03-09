# Speaker Diarization Implementation Plan

## Goal

Replace the current "You" / "Others" binary speaker labels with true multi-speaker diarization: identify each distinct voice in the audio, attribute every word to a speaker, and auto-assign participant names using calendar data + LLM reasoning. Quality is prioritised over performance.

## Pipeline Overview

```
Recording stops
    │
    ├──→ Speaker Diarization (identify who spoke when)
    │        ├─ Voice Activity Detection
    │        ├─ Speaker Embedding Extraction
    │        └─ Agglomerative Clustering
    │        → Output: [(speakerID, startTime, endTime)]
    │
    ├──→ Transcription (word-level timestamps)
    │        → Output: [(word, startTime, endTime)]
    │
    └──→ Alignment
             ├─ Map each word → speaker via timestamp overlap
             └─ Group consecutive same-speaker words into segments
             → Output: diarized transcript with "Speaker 1/2/3..."
                    │
                    ▼
             Speaker Naming (LLM)
                    ├─ Input: participant list from calendar + representative quotes per cluster
                    ├─ LLM assigns names to speaker IDs based on contextual clues
                    └─ Fallback: "Speaker 1", "Speaker 2" if no calendar data / insufficient clues
                    │
                    ▼
             Summarisation (existing pipeline, now with real names)
```

## Diarization Engine Options

Choose ONE. Listed in order of recommendation.

### Option A: Argmax SpeakerKit (Recommended)

The creators of WhisperKit ship [SpeakerKit](https://www.argmaxinc.com/blog/speakerkit) — a commercial on-device diarization framework purpose-built to pair with WhisperKit.

- ~4 min audio processed in ~1 second on Apple Silicon
- Matches pyannote SOTA accuracy across 13 benchmark datasets
- ~10 MB model, macOS 13+
- Designed to consume WhisperKit output directly (word-level timestamps → speaker-attributed segments)
- Requires Argmax Pro SDK subscription licence

**Why recommended:** Best accuracy-to-effort ratio. Eliminates the model conversion problem entirely. Already designed for the WhisperKit output format we use. Commercial cost is justified for a shipping product where quality matters.

**Integration path:** Add SPM dependency, call SpeakerKit after WhisperKit transcription, receive speaker-labelled segments directly.

### Option B: pyannote-audio via CoreML

Convert [pyannote-audio](https://github.com/pyannote/pyannote-audio) models to CoreML and run natively in Swift.

Models needed:
- `pyannote/segmentation-3.0` → CoreML (speaker segmentation)
- `pyannote/wespeaker-voxceleb-resnet34` → CoreML (speaker embeddings)

**Pros:** Open source, SOTA accuracy, no recurring cost
**Cons:** Significant one-time conversion effort, must maintain CoreML conversion pipeline as models update, must implement clustering in Swift

**Alternative:** Run models via ONNX Runtime for Swift instead of CoreML if conversion proves difficult.

### Option C: Apple SpeechAnalyzer (Future — macOS 26+)

Apple's SpeechAnalyzer framework (WWDC 2025) does not include diarization in its initial release. If Apple adds it in macOS 26.x or 27, it would be the ideal zero-dependency solution. Not actionable today.

## Implementation Steps

### Phase 1: Data Model Changes

**Files:** `TranscriptionResult.swift`, `MeetingTranscription`, `SegmentedTranscriptView.swift`

1. Add `speaker` field to `TranscriptSegment`:

```swift
struct TranscriptSegment: Codable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let speaker: String?  // nil = unknown/legacy, "Speaker 1", "Alice", etc.
}
```

2. `SpeakerSegment` (currently a view-layer struct) becomes redundant — remove it and read speaker directly from `TranscriptSegment.speaker`.

3. Update `MeetingTranscription`:
   - Replace `systemTranscript` + `micTranscript` with a single `transcript: TimestampedTranscript` containing all diarized segments
   - Keep old fields as optionals for backward compatibility with existing stored meetings
   - Add `isDiarized: Bool` computed property (true when any segment has a non-nil speaker)
   - Remove `interleavedSpeakerSegments()` — segments already carry speaker labels

```swift
struct MeetingTranscription: Codable {
    // New: single diarized transcript
    let transcript: TimestampedTranscript?

    // Legacy (kept for backward compat with stored meetings)
    let systemTranscript: TimestampedTranscript?
    let micTranscript: TimestampedTranscript?

    let combinedText: String
    let processingDuration: TimeInterval
    let modelUsed: String

    var isDiarized: Bool {
        transcript?.segments.contains { $0.speaker != nil } ?? false
    }

    var effectiveSegments: [TranscriptSegment] {
        if let transcript { return transcript.segments }
        // Legacy fallback: interleave system + mic
        ...
    }
}
```

4. Update `SegmentedTranscriptView` to read `segment.speaker` directly instead of using `SpeakerSegment`. Assign a consistent colour per speaker name (hash name → colour from a palette).

### Phase 2: WhisperKit Word-Level Timestamps

**File:** `TranscriptionService.swift`

Currently WhisperKit is a fallback path. For diarization, we need it as the primary transcription engine (SFSpeech doesn't provide word-level timestamps suitable for diarization alignment).

1. After recording stops, run WhisperKit with word-level timestamps enabled:

```swift
let result = try await whisperKit.transcribe(
    audioPath: audioURL.path,
    decodeOptions: DecodingOptions(wordTimestamps: true)
)
// result.allWords → [(word: String, start: TimeInterval, end: TimeInterval)]
```

2. SFSpeech continues to provide live text during recording (UX unchanged). WhisperKit runs post-recording for the final diarized transcript.

3. The SFSpeech live transcript is discarded after WhisperKit produces the final word-level result. This is a quality trade-off: WhisperKit with a large model produces more accurate text than SFSpeech.

### Phase 3: Speaker Diarization Service

**New file:** `Sources/Transcription/SpeakerDiarizationService.swift`

Core service that takes an audio file and returns speaker turns:

```swift
class SpeakerDiarizationService {
    struct SpeakerTurn {
        let speakerID: Int            // 0-indexed cluster label
        let startTime: TimeInterval
        let endTime: TimeInterval
    }

    struct DiarizationResult {
        let turns: [SpeakerTurn]
        let speakerCount: Int
    }

    /// Analyse audio and identify distinct speakers
    func diarize(audioURL: URL) async throws -> DiarizationResult
}
```

**Implementation depends on chosen engine:**

- **SpeakerKit:** Call SpeakerKit API with the audio file + WhisperKit word timestamps. It returns speaker-labelled segments directly. Minimal code needed.

- **pyannote/CoreML:** Load segmentation model, run sliding-window inference (10s frames, 2.5s step), extract embeddings per speech region, cluster with agglomerative clustering (cosine distance threshold ~0.7), merge adjacent same-speaker segments.

### Phase 4: Transcript–Speaker Alignment

**New file:** `Sources/Transcription/TranscriptAligner.swift`

Combines WhisperKit words with diarization speaker turns:

```swift
struct TranscriptAligner {
    /// Assign each word to a speaker based on timestamp overlap
    static func align(
        words: [WordTiming],
        speakerTurns: [SpeakerTurn]
    ) -> [TranscriptSegment] {
        // For each word, find the speaker turn with maximum overlap
        // Group consecutive words with the same speaker into segments
        // Return segments with speaker labels set
    }
}
```

**Algorithm:**
1. For each word, compute overlap duration with each speaker turn
2. Assign word to speaker with greatest overlap (ties go to the turn that started earlier)
3. Group consecutive same-speaker words into segments
4. Set `segment.speaker = "Speaker \(speakerID + 1)"` (names assigned later by LLM)

**If using SpeakerKit:** This step may be handled internally by SpeakerKit, making this class a thin wrapper or unnecessary.

### Phase 5: LLM Speaker Naming

**File:** `SummarizationService.swift` (extend existing)

After alignment produces a diarized transcript with "Speaker 1", "Speaker 2", etc., use the LLM to assign real names.

1. Add a new method: `identifySpeakers(transcript:participants:) async throws -> [Int: String]`

2. Build a prompt with:
   - The participant list from the calendar event (already available via `currentMeetingParticipants` / `MeetingRecord.decodedParticipants()`)
   - 3-5 representative quotes from each speaker cluster (pick quotes that are likely to contain self-identification or cross-references)

```
Prompt:
You are analysing a meeting transcript to identify speakers.

The meeting participants are: Alice Chen, Bob Smith, Carol Davis

Here are representative quotes from each speaker:

Speaker 1:
- "I'll push the backend changes after this call"
- "Bob, can you review my PR?"
- "As I mentioned in standup..."

Speaker 2:
- "Sure Alice, I'll take a look"
- "The frontend tests are passing now"
- "Carol and I paired on the auth flow"

Speaker 3:
- "The design specs are ready for review"
- "I updated the Figma file this morning"

Respond with a JSON object mapping speaker numbers to participant names.
Only assign a name if you are reasonably confident. Use "Unknown" otherwise.

{"1": "Alice Chen", "2": "Bob Smith", "3": "Carol Davis"}
```

3. Parse the LLM response and update speaker labels in the transcript segments.

4. **Fallback behaviour:**
   - No calendar participants → skip LLM naming, keep "Speaker 1/2/3"
   - LLM returns "Unknown" for a speaker → keep "Speaker N"
   - LLM call fails → keep "Speaker N" labels (non-fatal)

5. **Combine with summarisation:** The speaker naming could optionally be folded into the summarisation prompt itself (one LLM call instead of two). Trade-off: a single combined prompt is more efficient but harder to parse reliably. Recommend keeping them separate initially for debuggability, then combining later if the extra latency matters.

### Phase 6: AppState Integration

**File:** `AppState.swift`

Update the post-recording flow:

```
stopRecording()
    │
    ├─ Continue showing SFSpeech live text as "preliminary transcript"
    │
    ├─ phase = .transcribing (show progress)
    │
    ├─ Run in parallel:
    │   ├─ WhisperKit transcription (word-level timestamps)
    │   └─ Speaker diarization
    │
    ├─ Align words with speaker turns → diarized transcript
    │
    ├─ phase = .transcribed (show diarized transcript with "Speaker 1/2/3")
    │
    ├─ phase = .summarizing
    │   ├─ LLM speaker naming (if calendar participants available)
    │   ├─ Update transcript with real names
    │   └─ LLM summarisation (with named transcript)
    │
    └─ phase = .summarized (final result with named speakers + summary)
```

Key changes:
- WhisperKit and diarization run concurrently (they're independent — both just need the audio file)
- SFSpeech live text is still shown during recording (no UX change)
- The `.transcribing` phase now encompasses both WhisperKit + diarization
- Speaker naming happens in the `.summarizing` phase (it needs the LLM)

### Phase 7: UI Updates

**Files:** `SegmentedTranscriptView.swift`, `MeetingDetailView.swift`, `TranscriptionResultView.swift`

1. **Speaker colours:** Assign a consistent colour to each speaker from a palette (hash speaker name → index). Replace the current hardcoded blue/green for "Others"/"You".

2. **Speaker labels:** Show full speaker name (or "Speaker N") as a label before each speaker's text block, similar to current timestamp pills.

3. **Transcript copy:** When copying transcript as text, format as:
   ```
   [00:01:23] Alice: I think we should ship this week.
   [00:01:28] Bob: Agreed, the tests are green.
   ```

4. **Summary integration:** The summary already uses `{{participants}}` — with diarized transcripts, the LLM will naturally attribute quotes and action items to named speakers.

### Phase 8: Re-diarization of Existing Meetings

Allow users to re-process existing meetings with diarization (similar to existing re-summarize feature):

1. Add "Re-transcribe with diarization" button in `MeetingDetailView` for meetings that have audio files but weren't diarized
2. Loads audio from stored path, runs the full diarization pipeline
3. Updates the meeting record in the database with the new diarized transcript

## Data Flow: Calendar Participants → Speaker Names

The participant data already flows through the system:

```
EventKit / Google Calendar
    → CalendarMeeting.participants: [String]
    → AppState.currentMeetingParticipants
    → MeetingStore.updateWithCalendarInfo() → DB (participantsJSON)
    → SummarizationService.summarize(participants:)
```

For speaker naming, tap into this at summarisation time:
```swift
let participants = currentMeetingParticipants
    ?? meetingStore.loadMeeting(id: id)?.decodedParticipants()

let speakerMap = try await summarizationService.identifySpeakers(
    transcript: diarizedTranscript,
    participants: participants  // may be nil — that's fine
)
```

## Dependencies

| Engine Choice | New Dependencies | Licence |
|---------------|-----------------|---------|
| SpeakerKit | `argmaxinc/SpeakerKit` (SPM) | Commercial (Argmax Pro SDK) |
| pyannote/CoreML | CoreML models (bundled or downloaded), possibly `onnxruntime-swift` | MIT (pyannote), Apache 2.0 (ONNX Runtime) |

WhisperKit is already a dependency. No other new dependencies required.

## Processing Time Estimates (1-hour meeting, M2 Pro)

| Step | SpeakerKit | pyannote/CoreML |
|------|-----------|-----------------|
| Diarization | ~15 seconds | ~60-120 seconds |
| WhisperKit (large-v3, word timestamps) | ~3-5 minutes | ~3-5 minutes |
| Alignment | <1 second | <1 second |
| LLM speaker naming | ~10-20 seconds | ~10-20 seconds |
| LLM summarisation | ~30-60 seconds | ~30-60 seconds |
| **Total** | **~4-7 minutes** | **~5-8 minutes** |

Diarization and WhisperKit run concurrently, so the wall-clock time is dominated by WhisperKit.

## Migration & Backward Compatibility

- Existing stored `MeetingTranscription` JSON (with `systemTranscript` / `micTranscript`) must continue to decode. Use optional fields + computed `effectiveSegments` accessor.
- `TranscriptSegment.speaker` is optional — nil for legacy segments.
- `SegmentedTranscriptView` falls back to current "You"/"Others" display when `isDiarized` is false.
- No database migration needed — transcription is stored as JSON blob in `transcriptionJSON` column. The new format just has richer content.

## Out of Scope (for now)

- Real-time diarization during recording (batch post-recording only)
- Speaker identification across meetings ("this voice is always Alice") — would need a persistent voice profile database
- Manual speaker correction UI (user renames "Speaker 2" → "Dave") — trivially addable later but not in v1
- Training/fine-tuning speaker models on user's voice
