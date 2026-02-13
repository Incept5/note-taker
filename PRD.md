# Note Taker - Product Requirements Document

**Version:** 0.3 (Draft)
**Date:** 2025-02-13
**Status:** Initial Draft

---

## Problem Statement

Professionals need to capture and summarize conversations from meetings, calls, and discussions. Existing solutions like Granola send audio data to cloud-based transcription services (Deepgram, AssemblyAI) and cloud LLMs (OpenAI, Anthropic) for summarization. While these services may contractually agree not to train on your data, the audio and transcripts still transit through and are processed on third-party infrastructure — creating privacy and compliance risks for industries handling sensitive information (legal, healthcare, finance, government).

## Market Context & Competitive Landscape

### Granola (Cloud-Based Approach)
Granola is the leading product in this space. It captures mic + system audio and streams it in real-time to cloud transcription providers (Deepgram, AssemblyAI). Summaries are generated via cloud LLMs (OpenAI, Anthropic). Audio is not stored — it's transcribed in real-time and discarded. Notes are stored in AWS (US-hosted VPC). Granola is SOC 2 Type 2 certified and GDPR compliant.

**Granola's trade-off:** Polished UX, high transcription accuracy, no hardware requirements — but your conversation audio passes through cloud infrastructure and your transcripts/summaries are stored on their servers.

### Recap (Open Source, Local-First)
[Recap](https://github.com/RecapAI/Recap) is an open-source macOS-native project solving the same problem with a local-first approach. It uses Core Audio Taps for system audio capture, WhisperKit (MLX) for local transcription, and Ollama for local summarization. It is currently incomplete and not recommended for production use, but validates that the fully-local technical approach is viable.

**Recap's limitations:** Early/broken state, requires macOS 15+, needs 16GB+ RAM (32GB recommended), limited UX polish, no automatic meeting detection yet.

#### Recap Codebase Analysis (Deep Dive)

We performed a detailed analysis of Recap's codebase. Key findings:

**What works and is valuable as reference:**
- **Core Audio Taps implementation** (`ProcessTap.swift`) — demonstrates `AudioHardwareCreateProcessTap()` for driver-free system audio capture. Creates an aggregate audio device, registers an I/O callback, writes buffers to WAV files on a high-priority dispatch queue. This is the most valuable reference code.
- **Dual audio stream architecture** — mic (via `AVAudioEngine`) and system audio (via `ProcessTap`) are captured as separate WAV files, transcribed independently, then combined with annotation. This gives "you vs others" speaker separation for free.
- **WhisperKit integration** — models downloaded from Hugging Face, cached locally, transcription via `whisperKit.transcribe(audioPath)`. Batch-only (not streaming).
- **LLM provider abstraction** — clean `LLMProviderType` protocol with Ollama and OpenRouter as concrete implementations. Ollama communicates on `localhost:11434`.
- **Protocol-oriented design** — 30+ protocols for testability and dependency injection via a factory container (`DependencyContainer`).

**What's broken or incomplete:**
- README explicitly states "broken in its current state"
- Auto-stop recording when meeting ends — not implemented (flag exists, logic not connected)
- Live/streaming transcription — batch only, no real-time feedback during recording
- Structured summary extraction — `keyPoints` and `actionItems` fields are empty stubs; summary is unstructured text
- `fatalError` in CoreDataManager — app crashes if Core Data can't initialize
- Meeting detection is fragile — polls window titles every 1 second via ScreenCaptureKit regex matching
- Keychain integration incomplete — API keys stored as environment variables
- Test coverage ~30% (target was 85%)

**Architecture decisions we should adopt:**
- Separate audio streams (mic vs system) as independent capture paths
- Core Audio Taps for system audio (proven to work without drivers)
- WhisperKit for transcription (MLX-optimized, ~2% WER)
- Ollama for local LLM summarization
- Protocol-oriented design for testability

**Architecture decisions we should improve on:**
- Core Data is heavyweight for this use case — SQLite or filesystem-based storage is simpler
- Batch-only transcription means users wait after stopping — we should explore streaming
- Unstructured summary text — we should use structured prompts to extract key points, decisions, action items as distinct fields
- No error recovery — we need graceful degradation, not `fatalError`
- Meeting detection via window title polling is brittle — defer this feature rather than ship it broken

### The Cloud vs Local Trade-off

This is the fundamental architectural distinction in this space:

| | Cloud (Granola) | Local (Note Taker) |
|---|---|---|
| **Audio processing** | Streamed to cloud providers | Processed entirely on-device |
| **Transcription** | Cloud ASR (Deepgram, AssemblyAI) — high accuracy, no hardware cost | Local model (WhisperKit/Whisper.cpp) — comparable accuracy, requires Apple Silicon |
| **Summarization** | Cloud LLMs (GPT-4, Claude) — highest quality | Local LLM (Ollama) — good quality, improving rapidly, requires 16GB+ RAM |
| **Data residency** | AWS servers (encrypted, SOC 2) | Never leaves user's machine |
| **Hardware requirements** | Minimal | Apple Silicon Mac, 16GB+ RAM |
| **Offline capability** | None — requires internet | Fully offline |
| **Accuracy ceiling** | Higher (cloud models are larger) | Slightly lower but closing fast |
| **Privacy guarantee** | Contractual (trust the provider) | Architectural (data physically cannot leave) |

**Our position:** We choose the local approach. The privacy guarantee is architectural, not contractual — conversation data *physically cannot* leave the user's machine because no network calls are made during the entire pipeline. This is a stronger guarantee than any cloud provider can offer, regardless of their certifications.

## Product Vision

Note Taker is a **privacy-first** conversation capture and summarization tool. It captures all audio from meetings — both the user's microphone and system audio (e.g. remote participants on Zoom/Teams) — transcribes speech locally, and generates meeting summaries using a **local LLM** — ensuring no conversation data ever leaves the user's machine.

## Target Users

- Professionals in privacy-sensitive industries (legal, healthcare, finance, government)
- Anyone who wants meeting notes without cloud data exposure
- Teams operating under strict data governance or compliance policies
- Security-conscious individuals who prefer architectural privacy guarantees over contractual ones

## Core Features (MVP)

### 1. Audio Capture
- Capture audio from the built-in microphone (user's voice)
- Capture system audio output (remote participants via Zoom, Teams, Meet, etc.) using Core Audio Taps
- Separate mic and system audio streams (enables speaker attribution — "you" vs "others")
- Simple start/stop controls
- Visual indicator that recording is active
- Support for conversations of up to 2 hours

### 2. Local Transcription
- Speech-to-text using WhisperKit (MLX-optimized for Apple Silicon)
- Near-real-time transcription
- Basic speaker separation: user (mic) vs remote participants (system audio)
- Speaker diarization within remote audio — stretch goal for MVP
- Support for English initially

### 3. Conversation Summary
- Generate a structured summary at the end of a conversation using a local LLM (via Ollama)
- Summary should include:
  - Key discussion points
  - Decisions made
  - Action items with owners (where identifiable)
  - Open questions
- User can regenerate or refine the summary

### 4. Data Storage
- All data stored locally on the user's machine
- Transcripts and summaries saved in a searchable format
- User can delete recordings, transcripts, and summaries at any time

## Non-Functional Requirements

### Privacy & Security
- **Zero cloud dependency** for audio processing, transcription, and summarization
- No telemetry or data collection
- All data encrypted at rest
- No network calls during recording/transcription/summarization pipeline
- Application should be verifiably offline during the capture-to-summary pipeline (ideally, users can confirm no network activity)

### Performance
- Transcription should keep pace with or slightly trail real-time on M-series Macs
- Summary generation should complete within 60 seconds of conversation end
- Application should not degrade system performance significantly during recording

### Platform & Hardware
- macOS desktop application (initial target)
- Requires macOS 14+ (Sonoma) for Core Audio Taps
- Requires Apple Silicon (M1 minimum, M2 Pro+ recommended)
- Minimum 16GB RAM (32GB recommended for best LLM performance)
- Windows and Linux as future targets

## Technical Approach

| Component | Technology | Notes |
|---|---|---|
| Mic capture | CoreAudio (AVAudioEngine) | Standard macOS audio input |
| System audio capture | Core Audio Taps (`AudioHardwareCreateProcessTap`) | Driver-free, macOS 14+, Apple-recommended for audio-only capture |
| Speech-to-text | WhisperKit (MLX) | Apple Silicon optimized, ~2% WER, on-device |
| Local LLM | Ollama | Runs Mistral/Llama 3/etc locally, simple HTTP API on localhost |
| Application shell | Native macOS (Swift/SwiftUI) | Best performance, native audio API access, smallest footprint |
| Storage | SQLite + filesystem | Lightweight, no Core Data overhead |

### Why Native macOS (Swift/SwiftUI)?

Given our reliance on Core Audio Taps, WhisperKit (Swift package), and Apple Silicon optimizations, a native macOS app is the natural choice. Electron/Tauri would add overhead and complexity for wrapping APIs we need native access to anyway. This does mean macOS-only for now, but that aligns with our Apple Silicon hardware requirement.

### Decision: Build Fresh, Reference Recap

We will build from scratch rather than forking Recap. Reasons:
- Recap is explicitly broken and incomplete
- Core Data adds unnecessary complexity — we prefer SQLite/filesystem
- Their architecture has production-quality issues (`fatalError`, missing error recovery)
- We want structured summary output, not unstructured text
- We want to explore streaming transcription, not just batch

However, Recap's `ProcessTap.swift` and dual-stream audio architecture are valuable references for our Core Audio Taps implementation. We will study these patterns closely.

## Out of Scope (MVP)

- Multi-language support
- Cloud sync or backup
- Collaborative features
- Real-time summary during conversation
- Calendar integration
- Automatic meeting detection
- Windows/Linux support

### Why No Mobile App

Mobile is not just deferred — it's architecturally incompatible with our core value proposition. The key constraints:

| Capability | macOS (our platform) | iOS |
|---|---|---|
| Capture other apps' audio (Zoom, Teams) | Core Audio Taps — works | **Impossible** — iOS sandboxing prevents tapping into another app's audio output |
| Run local LLM (Ollama) | Runs as localhost server | **Cannot run** — too resource-intensive, no background server support on iOS |
| Local transcription (WhisperKit) | Fast on Apple Silicon Macs | Works but slower, significant battery drain |
| Background recording | Fully supported | Heavily restricted by iOS |

The dealbreaker is system audio capture. On iOS, you cannot access another app's audio — meaning you could only record the device microphone. For a phone/video call, you'd only hear the user's side (and a degraded speakerphone version of the remote side, if on speaker). This fundamentally breaks the "capture the full conversation" promise.

If a mobile product were ever built, it would be a **different product** — limited to in-person meeting capture via microphone, with smaller on-device models or a compromise on the "no cloud" privacy guarantee. We will not design the desktop architecture to accommodate this hypothetical; we'll keep the desktop app focused and well-separated, which is sufficient if mobile is ever revisited.

## Open Questions

1. **LLM model selection** — Which local model balances summary quality and performance? Llama 3 8B? Mistral 7B? Something larger for 32GB machines?
2. **Speaker diarization** — Include in MVP or defer? We get basic "you vs others" for free from separate audio streams, but identifying individual remote speakers adds complexity.
3. **Transcript editing** — Should users be able to edit transcripts before generating summaries?
4. **Audio retention** — Should we keep the raw audio, or discard after transcription (like Granola does) to minimize storage and data exposure?
5. **Streaming vs batch transcription** — WhisperKit supports batch. Streaming would give real-time feedback but adds complexity. Worth it for MVP?

## Success Metrics

- Transcription accuracy > 90% for clear English speech (WhisperKit benchmarks suggest ~98% is achievable)
- Summary captures all key action items from a conversation
- End-to-end pipeline (record -> transcribe -> summarize) works fully offline
- Application runs comfortably on M1 Mac with 16GB RAM

---

*This is a living document. Next steps: define application architecture, prototype audio capture with Core Audio Taps, and validate WhisperKit transcription quality.*
