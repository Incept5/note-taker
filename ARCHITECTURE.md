# Note Taker - Application Architecture

**Version:** 1.1.3
**Date:** 2026-02-20

---

## Overview

Note Taker is a native macOS menu bar application built with Swift/SwiftUI. It captures meeting audio (mic + system), transcribes it locally using WhisperKit, and generates structured summaries using a local LLM (MLX or Ollama). No data leaves the machine.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Menu Bar UI                          │
│                      (SwiftUI Views)                        │
├─────────────────────────────────────────────────────────────┤
│                       View Models                           │
│              (RecordingVM, SummaryVM, HistoryVM)             │
├─────────────────────────────────────────────────────────────┤
│                        Services                             │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────────┐  │
│  │ AudioCapture  │  │ Transcription │  │  Summarization   │  │
│  │   Service     │  │   Service     │  │    Service       │  │
│  └──────┬───────┘  └───────┬───────┘  └────────┬─────────┘  │
│         │                  │                    │            │
│  ┌──────┴───────┐  ┌──────┴────────┐  ┌───────┴──────────┐ │
│  │ SCStream     │  │  WhisperKit   │  │  MLX / Ollama    │ │
│  │ + AVAudio    │  │    (MLX)      │  │(local or remote) │ │
│  └──────────────┘  └───────────────┘  └──────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                     Storage Layer                           │
│              (SQLite + Filesystem for audio)                │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
NoteTaker/
├── App/
│   ├── NoteTakerApp.swift              # @main entry point
│   ├── AppState.swift                  # Global app state (ObservableObject)
│   ├── SettingsWindowController.swift  # Settings window management
│   └── Dependencies.swift             # Service factory / DI container
│
├── Audio/
│   ├── SystemAudioCapture.swift        # ScreenCaptureKit audio capture
│   ├── MicrophoneCapture.swift         # AVAudioEngine mic capture
│   ├── AudioCaptureService.swift       # Coordinates both streams
│   ├── AudioDeviceManager.swift        # Input device enumeration + hot-plug
│   ├── AudioLevelMonitor.swift         # Real-time audio level monitoring
│   └── CoreAudioUtils.swift            # Error types + AudioObjectID helpers
│
├── Transcription/
│   ├── TranscriptionService.swift      # WhisperKit batch transcription
│   ├── StreamingTranscriber.swift      # Real-time streaming transcription
│   ├── TranscriptionResult.swift       # Structured result type
│   └── ModelManager.swift             # Whisper model download/cache
│
├── Summarization/
│   ├── SummarizationService.swift      # Ollama integration
│   ├── SummaryResult.swift             # Structured summary type
│   └── PromptTemplates.swift          # Summary prompt engineering
│
├── Storage/
│   ├── Database.swift                  # SQLite wrapper
│   ├── MeetingRecord.swift            # Data model
│   └── FileStore.swift                # Audio file management
│
├── Views/
│   ├── MenuBar/
│   │   ├── MenuBarController.swift     # NSStatusItem management
│   │   └── PopoverView.swift          # Main popover container
│   ├── Recording/
│   │   ├── RecordingView.swift        # Start/stop UI + audio levels
│   │   └── AppPickerView.swift        # Select which app to capture
│   ├── Summary/
│   │   ├── SummaryView.swift          # Display structured summary
│   │   └── TranscriptView.swift       # Display full transcript
│   └── History/
│       └── HistoryView.swift          # Past meetings list
│
├── ViewModels/
│   ├── RecordingViewModel.swift        # Recording state + controls
│   ├── SummaryViewModel.swift          # Summary display + regeneration
│   └── HistoryViewModel.swift          # Past meetings
│
└── Shared/
    ├── Errors.swift                    # App-wide error types
    ├── Protocols.swift                 # Service protocols
    └── Extensions.swift               # Utility extensions
```

## Core Data Flow

### Recording Pipeline

```
User taps "Start" in menu bar
         │
         ▼
┌─ AudioCaptureService.startCapture(appProcess) ─────────────┐
│                                                             │
│  ┌─────────────────────┐    ┌────────────────────────────┐  │
│  │  SystemAudioCapture  │    │    MicrophoneCapture       │  │
│  │                      │    │                            │  │
│  │  ScreenCaptureKit    │    │  AVAudioEngine             │  │
│  │  SCStream (audio     │    │  inputNode → mixerNode     │  │
│  │  only, all apps)     │    │                            │  │
│  │       │              │    │       │                    │  │
│  │       ▼              │    │       ▼                    │  │
│  │  system.wav          │    │  mic.wav                   │  │
│  └───────┬─────────────┘    └────────────────────────────┘  │
│          │                                                   │
│          │ onAudioBuffer (48kHz stereo)                      │
│          ▼                                                   │
│  ┌─────────────────────┐                                    │
│  │ StreamingTranscriber │  ← downsample to 16kHz mono       │
│  │                      │  ← WhisperKit every 10s on        │
│  │  Live transcript     │    trailing 30s window            │
│  │  segments → UI       │  ← segments displayed in          │
│  │                      │    RecordingView live              │
│  └─────────────────────┘                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
User taps "Stop"
         │
         ▼
┌─ Transcription ────────────────────────────────────────────┐
│                                                             │
│  If streaming segments available:                           │
│    → Reuse streaming transcript for system audio            │
│    → Only transcribe mic.wav from file via WhisperKit       │
│  Else (fallback):                                           │
│    → Batch-transcribe both files via WhisperKit             │
│                                                             │
│  → systemTranscript (what others said)                      │
│  → micTranscript (what you said)                            │
│  → combinedTranscript (interleaved by timestamp)            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─ SummarizationService.summarize(transcript) ───────────────┐
│                                                             │
│  MLX (default) or Ollama (localhost:11434 or remote)        │
│  Structured prompt → JSON response                          │
│                                                             │
│  Returns:                                                   │
│  {                                                          │
│    "summary": "...",                                        │
│    "keyPoints": ["..."],                                    │
│    "decisions": ["..."],                                    │
│    "actionItems": [{"task": "...", "owner": "..."}],        │
│    "openQuestions": ["..."]                                  │
│  }                                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─ Storage ──────────────────────────────────────────────────┐
│                                                             │
│  SQLite: meeting record (metadata, transcript, summary)     │
│  Filesystem: audio files (optional retention)               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Audio Capture

#### SystemAudioCapture (ScreenCaptureKit)

Captures all system audio using ScreenCaptureKit's `SCStream` in audio-only mode. Replaced the previous Core Audio Taps approach (`AudioHardwareCreateProcessTap`) which delivered silent buffers in many configurations (Bluetooth output, stale TCC entries, permission edge cases).

```
Key APIs:
- SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:) — verify permission and get display info
- SCStream — audio capture stream with SCStreamConfiguration
- SCStreamOutput — delegate receiving CMSampleBuffer audio callbacks

Lifecycle:
1. init(fileURL:) — create audio file with 48kHz stereo float32 format
2. start() — async; create SCStream, add audio output, start capture
3. stream(_:didOutputSampleBuffer:of:) — extract audio, write to WAV
4. stop() — stop capture, close file

Configuration:
- capturesAudio = true, excludesCurrentProcessAudio = true
- captureMicrophone = false (macOS 15+) — mic handled separately
- Minimal video config (2x2px, 1fps) to reduce overhead

Requirements:
- macOS 14.2+ (Sonoma)
- Screen Recording permission (no video is actually recorded)
- Works with all output devices including Bluetooth
```

#### MicrophoneCapture (AVAudioEngine)

Standard microphone capture. Simpler than system audio.

```
Lifecycle:
1. prepare() — create AVAudioEngine, attach mixer node, connect input → mixer
2. start(outputURL) — install tap on mixer, start engine, write to WAV
3. stop() — remove tap, stop engine, close file
```

#### AudioCaptureService (Coordinator)

Manages both capture paths. Provides a single interface to the rest of the app.

```swift
@MainActor
final class AudioCaptureService: ObservableObject {
    func startCapture(inputDeviceID: AudioDeviceID? = nil) async throws
    func stopCapture() -> CapturedAudio?
    var isRecording: Bool { get }
    var systemAudioLevel: Float { get }  // for UI meters
    var micAudioLevel: Float { get }
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?  // for streaming transcription
}

struct CapturedAudio {
    let systemAudioURL: URL
    let microphoneURL: URL
    let directory: URL
    let startedAt: Date
    let duration: TimeInterval
}
```

### 2. Transcription

#### TranscriptionService

Wraps WhisperKit. Transcribes audio files to text.

```swift
protocol TranscriptionServiceProtocol {
    func transcribe(audio: CapturedAudio) async throws -> TranscriptionResult
    var availableModels: [WhisperModel] { get }
    func downloadModel(_ model: WhisperModel) async throws
}

struct TranscriptionResult {
    let systemTranscript: TimestampedTranscript  // what others said
    let micTranscript: TimestampedTranscript?    // what you said
    let combined: String                          // merged, readable
    let duration: TimeInterval                    // processing time
    let modelUsed: String
}

struct TimestampedTranscript {
    let segments: [TranscriptSegment]
    let fullText: String
}

struct TranscriptSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}
```

#### StreamingTranscriber

Real-time transcription during recording. Receives raw audio buffers from ScreenCaptureKit, accumulates and downsamples them, and periodically runs WhisperKit on a sliding window.

```
Audio pipeline (runs on audio queue):
1. appendBuffer() — receives 48kHz stereo float32 PCM buffers
2. Convert to mono (average L+R channels)
3. Downsample to 16kHz (take every 3rd sample)
4. Append to thread-safe AudioSampleAccumulator

Transcription loop (runs on main actor):
1. Timer fires every 10 seconds
2. Snapshot last 30s of accumulated 16kHz samples
3. Run WhisperKit.transcribe(audioArray:) on the window
4. Merge new segments with existing (deduplicate overlaps)
5. Publish updated segments → AppState → RecordingView

On stop:
- Streaming segments reused as system transcript
- Only mic audio needs batch transcription from file
```

Key design decisions:
- **Separate transcription of each stream** — preserves speaker attribution
- **Timestamps on segments** — enables interleaving mic and system transcripts chronologically
- **Model management** — download models on first run, cache locally
- **Streaming is best-effort** — if model fails to load, recording continues without live transcript; batch transcription is used as fallback on stop

### 3. Summarization

#### SummarizationService

Communicates with Ollama's HTTP API to generate structured summaries.

```swift
protocol SummarizationServiceProtocol {
    func summarize(transcript: String, context: MeetingContext) async throws -> SummaryResult
    func regenerate(transcript: String, context: MeetingContext, userFeedback: String) async throws -> SummaryResult
    var isOllamaAvailable: Bool { get }
}

struct MeetingContext {
    let duration: TimeInterval
    let participantCount: Int?  // if detectable
    let appName: String?        // "Zoom", "Teams", etc.
}

struct SummaryResult {
    let summary: String              // narrative overview
    let keyPoints: [String]          // bullet points
    let decisions: [String]          // what was decided
    let actionItems: [ActionItem]    // tasks with owners
    let openQuestions: [String]      // unresolved topics
    let modelUsed: String
    let processingTime: TimeInterval
}

struct ActionItem {
    let task: String
    let owner: String?
}
```

Key design decisions:
- **Structured output** — prompt Ollama to return JSON, parse into distinct fields (unlike Recap's unstructured text)
- **Regeneration** — user can provide feedback ("focus more on action items") and regenerate
- **Ollama health check** — verify Ollama is running before attempting summarization, show clear error if not

#### Prompt Engineering

```
System prompt:
"You are a meeting summarizer. Analyze the transcript and return a JSON object with:
- summary: A 2-3 paragraph narrative summary
- keyPoints: Array of key discussion points
- decisions: Array of decisions that were made
- actionItems: Array of {task, owner} objects
- openQuestions: Array of unresolved questions

Be concise. Focus on what matters. Attribute action items to specific people where possible."

User prompt:
"Meeting duration: {duration}
Application: {appName}

Transcript:
{transcript}"
```

### 4. Storage

#### SQLite Database

Lightweight storage for meeting records. No ORM, no Core Data — direct SQLite via a thin wrapper (e.g. GRDB.swift or raw SQLite3 C API).

```sql
CREATE TABLE meetings (
    id TEXT PRIMARY KEY,
    started_at DATETIME NOT NULL,
    ended_at DATETIME,
    duration_seconds REAL,
    app_name TEXT,

    -- Transcript
    system_transcript TEXT,
    mic_transcript TEXT,
    combined_transcript TEXT,

    -- Summary (stored as JSON)
    summary_json TEXT,

    -- File references
    system_audio_path TEXT,
    mic_audio_path TEXT,

    -- State
    status TEXT NOT NULL DEFAULT 'recording',  -- recording, transcribing, summarizing, completed, failed
    error_message TEXT,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

#### File Storage

Audio files stored in the app's Application Support directory:

```
~/Library/Application Support/NoteTaker/
├── audio/
│   ├── {meeting-id}/
│   │   ├── system.wav
│   │   └── mic.wav
├── models/
│   └── whisper/
│       └── {model-name}/
└── notetaker.db
```

### 5. UI Architecture

#### Menu Bar App

Note Taker lives in the macOS menu bar. No Dock icon, no main window — just a status item with a popover.

```
Menu Bar Icon (microphone icon)
    │
    ▼ click
┌─────────────────────────────┐
│         Popover             │
│                             │
│  ┌───────────────────────┐  │
│  │   [Not Recording]     │  │
│  │                       │  │
│  │   Select App: [Zoom▾] │  │
│  │                       │  │
│  │   [● Start Recording] │  │
│  └───────────────────────┘  │
│                             │
│  ┌───────────────────────┐  │
│  │   Recent Meetings     │  │
│  │   • Standup 10:00am   │  │
│  │   • Design Review 2pm │  │
│  └───────────────────────┘  │
│                             │
│  [Settings]  [History]      │
└─────────────────────────────┘
```

During recording:

```
┌─────────────────────────────┐
│         Popover             │
│                             │
│  ┌───────────────────────┐  │
│  │   ● Recording (12:34) │  │
│  │   App: Zoom            │  │
│  │                       │  │
│  │   System: ████░░░░░░  │  │
│  │   Mic:    ██░░░░░░░░  │  │
│  │                       │  │
│  │   ┌─ Live Transcript ┐│  │
│  │   │ 0:12 We need to  ││  │
│  │   │ 0:24 The budget  ││  │
│  │   │ 0:38 Let's move  ││  │
│  │   └──────────────────┘│  │
│  │                       │  │
│  │   [■ Stop Recording]  │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
```

After recording (processing → complete):

```
┌─────────────────────────────┐
│         Popover             │
│                             │
│  ┌───────────────────────┐  │
│  │   ✓ Meeting Complete   │  │
│  │   Duration: 45:12      │  │
│  │                       │  │
│  │   Summary             │  │
│  │   ─────────────────   │  │
│  │   Discussion covered   │  │
│  │   the Q1 roadmap...    │  │
│  │                       │  │
│  │   Key Points          │  │
│  │   • Budget approved    │  │
│  │   • Timeline shifted   │  │
│  │                       │  │
│  │   Action Items        │  │
│  │   □ @Alice: Draft PRD  │  │
│  │   □ @Bob: Update costs │  │
│  │                       │  │
│  │   [View Transcript]    │  │
│  │   [Regenerate Summary] │  │
│  │   [Copy to Clipboard]  │  │
│  └───────────────────────┘  │
└─────────────────────────────┘
```

#### View Structure

```
PopoverView (container)
├── RecordingView (start/stop, audio levels, app picker)
├── ProcessingView (transcribing/summarizing progress)
├── SummaryView (structured summary display)
├── TranscriptView (full transcript with speaker labels)
├── HistoryView (list of past meetings)
└── SettingsView (model selection, preferences)
```

### 6. State Management

Single `AppState` observable object drives the entire UI:

```swift
@MainActor
class AppState: ObservableObject {
    enum Phase {
        case idle
        case recording(since: Date, transcript: [TranscriptSegment])
        case transcribing(progress: Double)
        case summarizing
        case complete(MeetingRecord)
        case error(AppError)
    }

    @Published var phase: Phase = .idle
    @Published var systemAudioLevel: Float = 0
    @Published var micAudioLevel: Float = 0
    @Published var selectedApp: AudioProcess?
    @Published var recentMeetings: [MeetingRecord] = []
}
```

### 7. Error Handling Strategy

No `fatalError`. No crashes. Graceful degradation everywhere.

```swift
enum AppError: LocalizedError {
    // Audio
    case micPermissionDenied
    case systemAudioPermissionDenied
    case audioProcessNotFound
    case audioCaptureFailed(underlying: Error)

    // Transcription
    case whisperModelNotDownloaded
    case transcriptionFailed(underlying: Error)

    // Summarization
    case ollamaNotRunning
    case ollamaModelNotAvailable(model: String)
    case summarizationFailed(underlying: Error)

    // Storage
    case storageFull
    case databaseError(underlying: Error)
}
```

Each error maps to a user-facing message and a recovery action:
- `ollamaNotRunning` → "Ollama is not running. Please start Ollama and try again." + link to Ollama docs
- `whisperModelNotDownloaded` → "Whisper model needs to be downloaded first." + download button
- `micPermissionDenied` → "Microphone access required." + open System Settings button

### 8. Dependencies

| Package | Purpose | Notes |
|---|---|---|
| WhisperKit | Local speech-to-text | Swift package, MLX-optimized |
| mlx-swift-lm | Local LLM inference | Default summarization backend |
| GRDB.swift | SQLite wrapper | Lightweight, Swift-native, no Core Data |

Ollama is an optional external dependency (user installs separately) accessed via HTTP. Defaults to `http://localhost:11434` but configurable to a remote server via Settings. No Swift package needed — just `URLSession` calls to the configured Ollama base URL.

### 9. Permissions Required

| Permission | Why | API |
|---|---|---|
| Microphone | Capture user's voice | AVAudioEngine (triggers system prompt) |
| Screen Recording | ScreenCaptureKit for system audio | SCStream (triggers system prompt) |

Note: ScreenCaptureKit requires the Screen Recording permission on macOS, even though we only capture audio (no video). The permission dialog references screen recording — this is explained in the onboarding flow. If permission appears granted but capture fails (common after debug rebuilds with ad-hoc signing), run `tccutil reset ScreenCapture com.incept5.NoteTaker` and re-grant.

## Build Phases

### Phase 1: Audio Capture Proof of Concept
- Get `ProcessTap` working (system audio from a running app)
- Get `MicrophoneCapture` working
- Write both to WAV files simultaneously
- Validate audio quality

### Phase 2: Transcription Integration
- Integrate WhisperKit
- Transcribe captured WAV files
- Validate accuracy
- Measure performance on M1/M2

### Phase 3: Summarization
- Integrate Ollama HTTP API
- Design and test prompts for structured JSON output
- Parse and display summaries

### Phase 4: UI Shell
- Menu bar app with popover
- Recording controls + audio level meters
- Summary display with structured sections
- Meeting history

### Phase 5: Polish
- Onboarding flow (permissions, model download, Ollama check)
- Error handling and recovery
- Settings (model selection, prompt customization)
- Data management (delete meetings, audio retention policy)

---

*Reference: Recap codebase at `recap-reference/` — used as architectural reference for the original Core Audio Taps implementation (since replaced with ScreenCaptureKit in v1.1.2).*
