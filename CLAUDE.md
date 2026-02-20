# Note Taker

## What is this project?

Note Taker is a **privacy-first meeting transcription and summarization app** for macOS. It captures system audio (Zoom, Teams, Meet, etc.) via ScreenCaptureKit with microphone input mixed in, transcribes locally using WhisperKit, and generates structured summaries using a local LLM (MLX or Ollama). No data ever leaves the machine.

Think Granola, but fully local — the privacy guarantee is architectural, not contractual.

## Key Documents

- `PRD.md` — Product requirements, competitive analysis (Granola vs local approach), feature scope
- `ARCHITECTURE.md` — Technical architecture, component design, data flow
- `CHANGELOG.md` — Release history and feature notes
- `TROUBLESHOOTING.md` — Common issues and fixes

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI (native macOS menu bar app, no Dock icon)
- **System audio capture:** ScreenCaptureKit (`SCStream` audio-only mode) — macOS 14.2+
- **Microphone capture:** AVAudioEngine, mixed into system audio via ring buffer
- **Transcription:** WhisperKit (MLX-optimized for Apple Silicon), real-time streaming + batch
- **Summarization:** MLX (default, no external deps) or Ollama (local/remote)
- **Storage:** SQLite (via GRDB.swift) + filesystem

## Platform Requirements

- macOS 14.2+ (Sonoma) — required for ScreenCaptureKit audio capture
- Apple Silicon (M1 minimum, M2 Pro+ recommended)
- 16GB RAM minimum (32GB recommended for LLM summarization)

## Project Setup

- Uses XcodeGen (`project.yml`) to generate the Xcode project
- Run `xcodegen generate` after cloning or modifying project structure
- Build with Xcode or `xcodebuild -project NoteTaker.xcodeproj -scheme NoteTaker build`

## Key Technical Decisions

- **ScreenCaptureKit for system audio** — replaced Core Audio Taps which delivered silent buffers in many configurations. Requires Screen Recording permission.
- **Mic mixed into system audio** — AVAudioEngine captures mic into a thread-safe ring buffer (`MicRingBuffer`), mixed into SCStream callback before writing to file. Produces a single combined WAV with all voices. Don't use `captureMicrophone = true` on macOS 15+ — it didn't deliver audio reliably.
- **Native macOS (not Electron/Tauri)** — deeply coupled to Apple APIs (ScreenCaptureKit, WhisperKit, AVAudioEngine). Native gives best performance and smallest footprint.
- **SQLite over Core Data** — lighter weight, simpler, no ORM overhead.
- **Structured summary output** — LLM prompted for JSON with distinct fields (key points, decisions, action items), not unstructured text.
- **No mobile** — iOS cannot tap into other apps' audio (sandboxing). A mobile version would be a fundamentally different product.
- **App Sandbox disabled** — required for ScreenCaptureKit system audio capture.

## Conventions

- No `fatalError` in production paths — use `guard`/`throw` with descriptive errors
- `@MainActor` for all UI state
- Weak self in all audio callbacks to prevent retain cycles
- Settings window uses hide (`orderOut`) instead of close — avoids NSHostingView teardown crashes
- Use `Task.detached` for long-running downloads (WhisperKit models) to avoid autorelease pool corruption on @MainActor
