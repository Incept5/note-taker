# NoteTaker

Privacy-first meeting transcription and summarization for macOS. Capture meeting audio, transcribe it with WhisperKit, and generate structured summaries with a local LLM via Ollama. No data ever leaves your machine.

Think [Granola](https://www.granola.so/), but fully local. The privacy guarantee is architectural, not contractual.

## How It Works

NoteTaker lives in your menu bar. Click to start recording — it captures your microphone and system audio (Zoom, Teams, Meet, etc.) simultaneously using separate audio streams. When you stop, it transcribes locally and generates a structured summary with key points, decisions, action items, and open questions. Everything stays on your machine.

```
Record (mic + system audio)
    -> Transcribe locally (WhisperKit)
        -> Summarize locally (Ollama)
            -> Browse & copy results
```

## Requirements

- **macOS 14.2+** (Sonoma) — required for Core Audio Taps
- **Apple Silicon** (M1 minimum, M2 Pro+ recommended)
- **16 GB RAM** minimum (32 GB recommended for larger LLM models)
- **[Ollama](https://ollama.com/)** installed with at least one model downloaded

## Installation

1. Download `NoteTaker dmg` from the [latest release](https://github.com/Incept5/note-taker/releases/latest)
2. Open the DMG and drag **NoteTaker** to your **Applications** folder
3. Launch NoteTaker from Applications — it appears in the **menu bar** (no Dock icon)

### First Launch Permissions

macOS will ask for two permissions:

| Permission | Why |
|---|---|
| **Microphone** | Captures your voice during meetings |
| **Screen Recording** | Required by macOS for Core Audio Taps to capture system audio (no video is recorded) |

Grant both, then restart NoteTaker if prompted.

### Setting Up Ollama

NoteTaker uses [Ollama](https://ollama.com/) for local summarization. Install it and pull a model:

```bash
# Install Ollama
brew install ollama

# Start the Ollama server
ollama serve

# Pull a model (in a separate terminal)
ollama pull qwen3-vl           # Recommended — excellent summarization quality
# or
ollama pull llama3.1:8b        # Good alternative, fast
# or
ollama pull llama3.1:70b       # Best quality, needs 48GB+ RAM
```

Ollama must be running (`ollama serve`) whenever you want to generate summaries. Transcription works without it.

### Using a Remote Ollama Server

By default NoteTaker connects to Ollama on `http://localhost:11434`. If you have a more powerful machine running Ollama on your network (e.g. a Mac Mini or Studio with more RAM for larger models), you can point NoteTaker at it:

1. Open **Settings** (gear icon in the menu bar popover)
2. Change the **Server URL** under Summarization to your remote machine's address (e.g. `http://192.168.1.50:11434`)
3. Click **Connect** — NoteTaker will check availability and list the models on that server

This lets you run larger models (70B+) on a dedicated machine while keeping NoteTaker lightweight on your laptop. Audio capture and transcription still run locally — only the summarization request is sent to the remote Ollama server.

## Usage

### Recording a Meeting

1. Click the NoteTaker icon in your menu bar
2. Select which app's audio to capture (Zoom, Teams, etc.)
3. Click **Start Recording**
4. Audio level meters show both system audio and your microphone
5. Click **Stop Recording** when done

### Transcription

Transcription starts automatically after you stop recording. NoteTaker uses WhisperKit (optimized for Apple Silicon) to transcribe both audio streams. The first run downloads the Whisper model (~1.5 GB).

### Summarization

If an Ollama model is selected and Ollama is running, summarization starts automatically after transcription. The summary includes:

- **Key Points** — important topics discussed
- **Decisions** — what was agreed on
- **Action Items** — tasks with owners where identifiable
- **Open Questions** — unresolved topics
- **Full Summary** — detailed narrative overview with paragraph breaks

### Copying Results

Both the summary (as markdown) and raw transcript have copy buttons. Paste into your notes app, email, or document of choice.

### Meeting History

All sessions are saved automatically to a local SQLite database. Click the clock icon in the popover to open the history window — a dedicated resizable window where you can browse past meetings and click to drill into a detail view with side-by-side summary and transcript, each with copy buttons.

## Architecture

```
Menu Bar UI (SwiftUI)
    |
AppState (Phase-driven state machine)
    |
    +-- AudioCaptureService
    |     +-- SystemAudioCapture (Core Audio Taps)
    |     +-- MicrophoneCapture (AVAudioEngine)
    |
    +-- TranscriptionService (WhisperKit)
    |
    +-- SummarizationService (Ollama HTTP API)
    |
    +-- MeetingStore (SQLite via GRDB)
```

**Audio capture** uses two independent streams: Core Audio Taps for system audio from the selected app, and AVAudioEngine for microphone input. Both write to WAV files in `~/Library/Application Support/NoteTaker/recordings/`.

**State management** is driven by a single `AppState` class with a `Phase` enum: idle -> recording -> stopped -> transcribing -> transcribed -> summarizing -> summarized. Each phase transition drives the UI.

**Storage** uses SQLite (via GRDB.swift) for meeting metadata, transcripts, and summaries. Audio files are stored on the filesystem.

### Key Technical Decisions

- **Core Audio Taps** (`AudioHardwareCreateProcessTap`) for driver-free system audio capture — no kernel extensions needed
- **Separate audio streams** — mic and system audio are captured and transcribed independently, then merged into a single chronological transcript sorted by timestamp
- **WhisperKit** for transcription — MLX-optimized for Apple Silicon, runs entirely on-device
- **Ollama** for summarization — defaults to localhost:11434, configurable to use a remote server for access to larger models
- **SQLite over Core Data** — lighter weight, simpler, no ORM overhead
- **Structured summary output** — Ollama is prompted to return JSON with distinct fields, not unstructured text
- **No sandbox** — required for Core Audio Taps to function

## For Developers

### Prerequisites

- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Ollama](https://ollama.com/) running locally for summarization testing

### Building from Source

```bash
git clone <repo-url>
cd note-taker

# Generate the Xcode project
xcodegen generate

# Build
xcodebuild -project NoteTaker.xcodeproj -scheme NoteTaker build
```

Or open `NoteTaker.xcodeproj` in Xcode and build from there.

### Project Structure

```
Sources/
  App/            AppState, AppDelegate (@main entry point)
  Audio/          SystemAudioCapture, MicrophoneCapture, AudioCaptureService,
                  AudioLevelMonitor, AudioProcessDiscovery, CoreAudioUtils
  Transcription/  TranscriptionService, ModelManager, MeetingTranscription
  Summarization/  SummarizationService, OllamaClient, MeetingSummary
  Storage/        DatabaseManager (GRDB), MeetingStore, MeetingRecord
  Models/         AudioProcess, CapturedAudio
  Views/          All SwiftUI views (popover, recording, transcription,
                  summary, history, settings)
Resources/        Info.plist, entitlements
Assets.xcassets/  App icon
```

### Dependencies

| Package | Version | Purpose |
|---|---|---|
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 0.15.0+ | Local speech-to-text (MLX-optimized) |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.0.0+ | SQLite database wrapper |

Ollama is an external runtime dependency, not a Swift package. It communicates via HTTP (default `localhost:11434`, configurable to a remote server).

### Building a Release (Signed DMG)

The release script archives, signs with Developer ID, notarizes with Apple, and packages a DMG.

**Prerequisites:**
- Apple Developer Program membership ($99/year)
- Developer ID Application certificate installed (Xcode -> Settings -> Accounts -> Manage Certificates)
- App-specific password from [appleid.apple.com](https://appleid.apple.com) (Sign-In and Security -> App-Specific Passwords)

```bash
TEAM_ID=YOUR_TEAM_ID \
APPLE_ID=you@example.com \
APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx \
./scripts/release.sh
```

Optional environment variables:
- `VERSION` — set the version string (e.g. `1.0.0`)
- `BUILD_NUMBER` — explicit build number (auto-increments if omitted)
- `OUTPUT_DIR` — output directory (default: `build/release`)

The signed and notarized DMG is written to `build/release/NoteTaker-{version}.dmg`.

### Notes for Contributors

- No `fatalError` in production paths — use `guard`/`throw` with descriptive errors
- `@MainActor` for all UI state and Core Audio Tap activation
- Weak self in all audio callbacks to prevent retain cycles
- App sandbox is disabled (required for Core Audio Taps)
- Screen Recording permission is required — without it, audio buffers will be silent

## Privacy

NoteTaker makes **zero network calls** for audio capture and transcription — WhisperKit runs entirely on-device. Summarization calls Ollama, which defaults to localhost. If you configure a remote Ollama server, the transcript text is sent to that server for summarization — but this is a machine you control on your own network, not a third-party cloud service. Audio files, transcripts, and summaries are stored locally in `~/Library/Application Support/NoteTaker/`. No telemetry, no analytics, no cloud sync.

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
