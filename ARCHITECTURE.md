# Note Taker - Application Architecture

**Version:** 0.1
**Date:** 2025-02-13

---

## Overview

Note Taker is a native macOS menu bar application built with Swift/SwiftUI. It captures meeting audio (mic + system), transcribes it locally using WhisperKit, and generates structured summaries using a local LLM via Ollama. No data leaves the machine.

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
│  │ ProcessTap   │  │  WhisperKit   │  │     Ollama       │ │
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
│   ├── SystemAudioCapture.swift        # Core Audio Taps wrapper
│   ├── MicrophoneCapture.swift         # AVAudioEngine mic capture
│   ├── AudioCaptureService.swift       # Coordinates both streams
│   └── AudioLevel.swift               # Real-time audio level monitoring
│
├── Transcription/
│   ├── TranscriptionService.swift      # WhisperKit integration
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
│  │  ProcessTap for      │    │  AVAudioEngine             │  │
│  │  selected app        │    │  inputNode → mixerNode     │  │
│  │  (Zoom, Teams, etc)  │    │                            │  │
│  │       │              │    │       │                    │  │
│  │       ▼              │    │       ▼                    │  │
│  │  system_audio.wav    │    │  mic_audio.wav             │  │
│  └─────────────────────┘    └────────────────────────────┘  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
User taps "Stop"
         │
         ▼
┌─ TranscriptionService.transcribe(systemAudio, micAudio) ───┐
│                                                             │
│  WhisperKit processes each file independently               │
│  → systemTranscript (what others said)                      │
│  → micTranscript (what you said)                            │
│  → combinedTranscript (interleaved by timestamp)            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
┌─ SummarizationService.summarize(transcript) ───────────────┐
│                                                             │
│  Ollama (localhost:11434 or configured remote server)       │
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

#### SystemAudioCapture (Core Audio Taps)

Captures audio output from a specific application (e.g. Zoom) using `AudioHardwareCreateProcessTap`. Based on patterns from Recap's `ProcessTap.swift`.

```
Key APIs:
- AudioHardwareCreateProcessTap() — create a tap on a process's audio
- AudioDeviceCreateIOProcIDWithBlock() — register I/O callback for audio buffers
- Aggregate device creation — virtual device combining output + tap

Lifecycle:
1. activate() — create tap + aggregate device
2. run() — start I/O proc, begin writing buffers to WAV
3. stop() — stop I/O proc, close file
4. invalidate() — destroy tap + aggregate device

Requirements:
- macOS 14+ (Sonoma)
- Audio process must be running and producing audio
- App needs appropriate permissions
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
protocol AudioCaptureServiceProtocol {
    func startCapture(systemProcess: AudioProcess, includeMic: Bool) async throws
    func stopCapture() async throws -> CapturedAudio
    var isCapturing: Bool { get }
    var systemAudioLevel: Float { get }  // for UI meters
    var micAudioLevel: Float { get }
}

struct CapturedAudio {
    let systemAudioURL: URL
    let micAudioURL: URL?
    let duration: TimeInterval
    let startedAt: Date
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

Key design decisions:
- **Separate transcription of each stream** — preserves speaker attribution
- **Timestamps on segments** — enables interleaving mic and system transcripts chronologically
- **Model management** — download models on first run, cache locally

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
        case recording(since: Date)
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
| GRDB.swift | SQLite wrapper | Lightweight, Swift-native, no Core Data |

Ollama is an external dependency (user installs separately) accessed via HTTP. Defaults to `http://localhost:11434` but configurable to a remote server via Settings. No Swift package needed — just `URLSession` calls to the configured Ollama base URL.

### 9. Permissions Required

| Permission | Why | API |
|---|---|---|
| Microphone | Capture user's voice | AVAudioEngine (triggers system prompt) |
| Screen Recording | Core Audio Taps for system audio | AudioHardwareCreateProcessTap (triggers system prompt) |
| Accessibility | Optional: detect running apps | NSWorkspace (no prompt needed) |

Note: Core Audio Taps requires the Screen Recording permission on macOS, even though we're not capturing video. This is a macOS quirk — the permission dialog will reference screen recording. We should explain this clearly in onboarding.

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

*Reference: Recap codebase at `recap-reference/` — particularly `Recap/Audio/Capture/Tap/ProcessTap.swift` for Core Audio Taps implementation.*
