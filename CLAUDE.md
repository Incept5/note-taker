# Note Taker

## What is this project?

Note Taker is a **privacy-first meeting transcription and summarization app** for macOS. It captures meeting audio (both your microphone and system audio from apps like Zoom/Teams), transcribes it locally using WhisperKit, and generates structured summaries using a local LLM via Ollama. No data ever leaves the machine.

Think Granola, but fully local — the privacy guarantee is architectural, not contractual.

## Key Documents

- `PRD.md` — Product requirements, competitive analysis (Granola vs local approach), feature scope
- `ARCHITECTURE.md` — Technical architecture, component design, data flow, build phases
- `recap-reference/` — Cloned Recap open-source project used as technical reference (not our code)

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI (native macOS menu bar app)
- **System audio capture:** Core Audio Taps (`AudioHardwareCreateProcessTap`) — macOS 14.2+
- **Microphone capture:** AVAudioEngine
- **Transcription:** WhisperKit (MLX-optimized for Apple Silicon) — Phase 2
- **Summarization:** Ollama (local LLM on localhost:11434) — Phase 3
- **Storage:** SQLite (via GRDB.swift) + filesystem — Phase 4
- **No external packages for Phase 1** — system frameworks only

## Build Phases

1. **Audio Capture PoC** (current) — capture system + mic audio to WAV files
2. **Transcription** — integrate WhisperKit, transcribe captured audio
3. **Summarization** — integrate Ollama, generate structured summaries
4. **UI & Storage** — full menu bar app, meeting history, SQLite persistence
5. **Polish** — onboarding, error handling, settings, data management

## Platform Requirements

- macOS 14.2+ (Sonoma) — required for Core Audio Taps
- Apple Silicon (M1 minimum, M2 Pro+ recommended)
- 16GB RAM minimum (32GB recommended for LLM summarization)

## Project Setup

- Uses XcodeGen (`project.yml`) to generate the Xcode project
- Run `xcodegen generate` after cloning or modifying project structure
- Build with Xcode or `xcodebuild -project NoteTaker.xcodeproj -scheme NoteTaker build`

## Key Technical Decisions

- **Build fresh, not fork Recap** — Recap validates the tech stack but is incomplete/broken. We reference their patterns (especially `ProcessTap.swift` for Core Audio Taps) but write our own code.
- **Native macOS (not Electron/Tauri)** — deeply coupled to Apple APIs (Core Audio Taps, WhisperKit Swift package, AVAudioEngine). Native gives best performance and smallest footprint.
- **SQLite over Core Data** — lighter weight, simpler, no ORM overhead.
- **Structured summary output** — prompt Ollama for JSON with distinct fields (key points, decisions, action items), not unstructured text.
- **No mobile** — iOS cannot tap into other apps' audio (sandboxing). A mobile version would be a fundamentally different product.

## Reference Code

The `recap-reference/` directory contains the cloned Recap project. Key files to reference:
- `Recap/Audio/Capture/Tap/ProcessTap.swift` — Core Audio Taps implementation
- `Recap/Audio/Core/Utils/CoreAudioUtils.swift` — AudioObjectID property reading helpers
- `Recap/Audio/Capture/MicrophoneCapture+AudioEngine.swift` — AVAudioEngine mic capture
- `Recap/Audio/Processing/AudioRecordingCoordinator/AudioRecordingCoordinator.swift` — dual stream coordination

## Conventions

- No `fatalError` in production paths — use `guard`/`throw` with descriptive errors
- Protocol-oriented design for testability (but don't over-abstract in early phases)
- `@MainActor` for all UI state and Core Audio Tap activation
- Weak self in all audio callbacks to prevent retain cycles
