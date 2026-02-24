# NoteTaker

Privacy-first meeting transcription and summarization for macOS. Capture meeting audio, transcribe it with WhisperKit, and generate structured summaries with a local LLM. No data ever leaves your machine.

Think [Granola](https://www.granola.so/), but fully local. The privacy guarantee is architectural, not contractual.

## How It Works

NoteTaker lives in your menu bar. Click to start recording — it captures system audio (Zoom, Teams, Meet, etc.) via ScreenCaptureKit and mixes in your microphone input, producing a single combined audio stream with all voices. Audio is transcribed in real-time during recording, with a live transcript displayed as you go. When you stop, it generates a structured summary with key points, decisions, action items, and open questions. Everything stays on your machine.

```
Record (system audio + mic mixed together)
    -> Stream-transcribe in real-time (WhisperKit)
    -> On stop: finalize transcript
        -> Summarize locally (MLX or Ollama)
            -> Browse & copy results
```

## Requirements

- **macOS 14.2+** (Sonoma) — required for ScreenCaptureKit audio capture
- **Apple Silicon** (M1 minimum, M2 Pro+ recommended)
- **16 GB RAM** minimum (32 GB recommended for larger LLM models)

## Installation

1. Download `NoteTaker dmg` from the [latest release](https://github.com/Incept5/note-taker/releases/latest)
2. Open the DMG and drag **NoteTaker** to your **Applications** folder
3. Launch NoteTaker from Applications — it appears in the **menu bar** (no Dock icon)

### First Launch Permissions

macOS will ask for two permissions:

| Permission | Why |
|---|---|
| **Microphone** | Captures your voice during meetings |
| **Screen Recording** | Required by macOS for ScreenCaptureKit to capture system audio (no video is recorded) |

Grant both, then restart NoteTaker if prompted.

### Summarization Setup

NoteTaker supports two backends for local summarization:

#### MLX (Default — No Setup Required)

MLX runs models directly on Apple Silicon with no external dependencies. On first use, open **Settings** and download an MLX model — everything is managed within the app. No terminal commands, no servers to run.

#### Ollama (Alternative)

If you prefer [Ollama](https://ollama.com/), switch the backend to Ollama in Settings, then install and start the server:

```bash
brew install ollama
ollama serve

# Pull a model (in a separate terminal)
ollama pull qwen3-vl           # Recommended — excellent summarization quality
```

Ollama must be running (`ollama serve`) whenever you want to generate summaries. Transcription works without it.

#### Using a Remote Ollama Server

If you have a more powerful machine running Ollama on your network (e.g. a Mac Mini or Studio with more RAM for larger models), you can point NoteTaker at it:

1. Open **Settings** (gear icon in the menu bar popover)
2. Switch the summarization backend to **Ollama**
3. Change the **Server URL** to your remote machine's address (e.g. `http://192.168.1.50:11434`)
4. Click **Connect** — NoteTaker will check availability and list the models on that server

This lets you run larger models (70B+) on a dedicated machine while keeping NoteTaker lightweight on your laptop. Audio capture and transcription still run locally — only the summarization request is sent to the remote Ollama server.

## Usage

### Auto-Record for Zoom & Teams

NoteTaker can automatically start recording when Zoom or Microsoft Teams launches, and stop when the meeting ends — no manual intervention needed.

1. Open **Settings** (gear icon) → **Audio Capture**
2. Enable **"Auto-record when meeting starts"**

When a monitored app launches, recording starts automatically. When the meeting ends (detected by 30 seconds of sustained audio silence), recording stops and the transcription/summarization pipeline kicks in. If the meeting app quits entirely, recording stops immediately.

Auto-stop only applies to auto-started recordings — manually started recordings are never stopped automatically.

### Microphone Settings

By default, microphone capture is **enabled** and uses the system default input device. Your mic audio is mixed into the system audio stream so all voices appear in the transcript.

Open **Settings** (gear icon) to:
- **Toggle microphone capture** on or off
- **Choose a specific microphone** — if you have an external USB mic or audio interface, select it from the device list

Your selection is remembered across restarts, and the device list updates automatically when you plug in or disconnect hardware.

### Recording a Meeting

1. Click the NoteTaker icon in your menu bar
2. Click **Start Recording**
3. An audio level meter shows the combined audio stream
4. A **live transcript** appears as audio is transcribed in real-time
5. Click **Stop Recording** when done

### Transcription

Audio is transcribed in real-time during recording — you see transcript segments appear every ~10 seconds. When you stop, the streaming transcript is kept, making post-recording processing fast. If streaming transcription is unavailable (e.g. model not downloaded), NoteTaker falls back to batch-transcribing from the audio file. The first run downloads the Whisper model (~1.5 GB).

### Summarization

If a summarization model is selected and available, summarization starts automatically after transcription. The summary includes:

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
    |     +-- SystemAudioCapture (ScreenCaptureKit + mic mixing)
    |
    +-- AudioDeviceManager (input device enumeration)
    |
    +-- TranscriptionService (WhisperKit batch)
    |     +-- StreamingTranscriber (real-time during recording)
    |
    +-- SummarizationService (MLX or Ollama)
    |
    +-- MeetingStore (SQLite via GRDB)
    |
    +-- MeetingAppMonitor (NSWorkspace launch/terminate detection)
```

**Audio capture** uses ScreenCaptureKit for system audio (all apps) with microphone input mixed in via AVAudioEngine. Mic samples are captured into a thread-safe ring buffer and added to the system audio stream in the SCStream callback, producing a single combined WAV file in `~/Library/Application Support/NoteTaker/recordings/`. During recording, audio buffers are also forwarded to a `StreamingTranscriber` that downsamples from 48kHz to 16kHz and runs WhisperKit every 10 seconds on a sliding 30-second window, producing a live transcript.

**State management** is driven by a single `AppState` class with a `Phase` enum: idle -> recording (with live transcript segments) -> stopped -> transcribing -> transcribed -> summarizing -> summarized. Each phase transition drives the UI.

**Storage** uses SQLite (via GRDB.swift) for meeting metadata, transcripts, and summaries. Audio files are stored on the filesystem.

### Key Technical Decisions

- **ScreenCaptureKit** for driver-free system audio capture — no kernel extensions needed, works reliably across all output devices including Bluetooth
- **Mixed audio stream** — mic input is mixed into the system audio stream in real-time via a ring buffer, producing a single combined recording with all voices
- **Streaming transcription** — audio is transcribed in real-time during recording via a sliding window (30s window, 10s interval), giving immediate feedback and faster post-recording processing
- **WhisperKit** for transcription — MLX-optimized for Apple Silicon, runs entirely on-device
- **MLX** for summarization (default) — runs local LLMs directly on Apple Silicon with no external dependencies. Ollama also supported as an alternative, configurable to use a remote server for access to larger models
- **SQLite over Core Data** — lighter weight, simpler, no ORM overhead
- **Structured summary output** — Ollama is prompted to return JSON with distinct fields, not unstructured text
- **No sandbox** — required for system audio capture to function

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
  App/            AppState, AppDelegate (@main entry point),
                  MeetingAppMonitor
  Audio/          SystemAudioCapture (ScreenCaptureKit + mic mixing),
                  AudioCaptureService, AudioDeviceManager, AudioLevelMonitor,
                  AudioProcessDiscovery, CoreAudioUtils
  Transcription/  TranscriptionService, StreamingTranscriber, ModelManager,
                  MeetingTranscription
  Summarization/  SummarizationService, MLXClient, MLXModelManager,
                  OllamaClient, MeetingSummary
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
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 2.0.0+ | Local LLM inference on Apple Silicon |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.0.0+ | SQLite database wrapper |

Ollama is an optional external runtime dependency (not a Swift package) for users who prefer it over MLX. It communicates via HTTP (default `localhost:11434`, configurable to a remote server).

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
- `@MainActor` for all UI state
- Weak self in all audio callbacks to prevent retain cycles
- App sandbox is disabled (required for system audio capture)
- Screen Recording permission is required — without it, ScreenCaptureKit cannot capture system audio

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for solutions to common issues, including permission problems when upgrading from a previous version.

## Privacy

NoteTaker makes **zero network calls** for audio capture, transcription, and summarization (when using MLX) — everything runs entirely on-device. If you use Ollama on a remote server, the transcript text is sent to that server for summarization — but this is a machine you control on your own network, not a third-party cloud service. Audio files, transcripts, and summaries are stored locally in `~/Library/Application Support/NoteTaker/`. No telemetry, no analytics, no cloud sync.

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
