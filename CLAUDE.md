# Note Taker

## What is this project?

Note Taker is a **privacy-first meeting transcription and summarization app** for macOS. It captures system audio (Zoom, Teams, Meet, etc.) via ScreenCaptureKit with microphone input mixed in, transcribes locally using WhisperKit, and generates structured summaries using a local LLM (MLX or Ollama). No data ever leaves the machine.

Think Granola, but fully local — the privacy guarantee is architectural, not contractual.

## Key Documents

- `PRD.md` — Product requirements, competitive analysis (Granola vs local approach), feature scope
- `ARCHITECTURE.md` — Technical architecture, component design, data flow
- `CHANGELOG.md` — Release history and feature notes
- `TROUBLESHOOTING.md` — Common issues and fixes
- `FutureEnhancements.md` — Planned features and roadmap (speaker diarization, etc.)

## Tech Stack

- **Language:** Swift
- **UI:** SwiftUI (native macOS menu bar app, no Dock icon)
- **System audio capture:** ScreenCaptureKit (`SCStream` audio-only mode) — macOS 14.2+
- **Microphone capture:** AVAudioEngine with voice processing (AEC), mixed into system audio via ring buffer
- **Live transcription:** SFSpeechRecognizer (Apple Speech framework, on-device) for real-time display during recording
- **Final transcription:** Live SFSpeech transcript buffer (primary) with WhisperKit batch fallback
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
- **Mic mixed into system audio** — AVAudioEngine captures mic into a thread-safe ring buffer (`MicRingBuffer`), mixed into SCStream callback before writing to file. Produces a single combined M4A with all voices. Voice processing (AEC) is enabled on the mic input via `setVoiceProcessingEnabled(true)` to cancel echo from the mic picking up speaker output. Ducking is disabled (`voiceProcessingOtherAudioDuckingConfiguration`) so system audio volume stays normal. Don't use `captureMicrophone = true` on macOS 15+ — it didn't deliver audio reliably.
- **AAC-compressed recordings** — Audio is written as AAC-compressed M4A (128kbps) instead of uncompressed WAV. ~15-20x smaller files (~50-80 MB vs ~1 GB for a 58-min meeting). `AVAudioFile` with `kAudioFormatMPEG4AAC` settings handles real-time compression from the float32 PCM buffers. WhisperKit reads M4A via AVFoundation.
- **Recording retention cleanup** — `AudioCaptureService.cleanupOldRecordings(retentionDays:)` deletes recording directories older than the configured retention period (default 28 days, configurable in Settings). Runs on app launch from `AppState.init`.
- **Native macOS (not Electron/Tauri)** — deeply coupled to Apple APIs (ScreenCaptureKit, WhisperKit, AVAudioEngine). Native gives best performance and smallest footprint.
- **SQLite over Core Data** — lighter weight, simpler, no ORM overhead.
- **Structured summary output** — LLM prompted for JSON with distinct fields (key points, decisions, action items), not unstructured text.
- **Segmented transcript display** — `SegmentedTranscriptView` groups segments into 10-second paragraphs with timestamp pills and speaker change detection. When mic is enabled, system ("Others") and mic ("You") segments are interleaved chronologically with colour-coded labels via `interleavedSpeakerSegments()` on `MeetingTranscription`. During recording, a `LiveTextView` shows flowing SFSpeech text (~15 visible lines) with scrollbar to review earlier transcript. The `.recording` phase carries `liveText: String` (not `[TranscriptSegment]`).
- **Auto-record for meeting apps** — `MeetingAppMonitor` subscribes to `NSWorkspace` launch/terminate notifications for Zoom (`us.zoom.xos`) and Teams (`com.microsoft.teams`). On launch, auto-starts recording if enabled. Meeting end is detected via rolling-window silence monitoring (85%+ of 45-second window silent) in `AppState`, with app termination as fallback. Manual recordings are never auto-stopped. `AutoRecordTrigger` enum distinguishes `.meetingApp(String)` vs `.calendarEvent(String)` triggers.
- **Calendar-driven auto-recording** — `CalendarPollingService` polls EventKit and Google Calendar every 60 seconds for events starting within the next 2 minutes. On match, auto-starts recording with participants pre-populated. `calendarAutoRecordEnabled` setting, off by default. A calendar end timer auto-stops recording 5 minutes after the event's scheduled end time. Deduplicates by `eventIdentifier` to avoid re-triggering. `CalendarMeeting` struct includes `start`/`end` dates. DB migration v3 adds `calendarEventId` and `calendarEventEnd` columns to meetings table.
- **Google Calendar integration** — App-owned OAuth client (embedded credentials, PKCE flow). Users click "Sign in with Google" — no Cloud project setup required. `CalendarService.findCurrentMeetingWithFallback()` tries EventKit first, falls back to Google Calendar API. Tokens stored in Data Protection Keychain (`kSecUseDataProtectionKeychain: true`) with all values cached in memory to avoid repeated Keychain access. `GoogleCalendarAuthService` exposes `isSignedIn`/`signedInEmail` as `@Published` properties (not computed from Keychain). `GoogleCalendarConfig` is an enum with static constants; auth uses a self-retaining localhost callback server (`LocalOAuthCallbackServer`). Participants included in LLM summarization prompt and displayed in meeting detail views.
- **Hybrid transcription: SFSpeech live + WhisperKit fallback** — `SpeechStreamingTranscriber` wraps `SFSpeechRecognizer` for near-instant word-by-word live text during recording. `AppState` accumulates live text into an append-only `liveTranscriptSegments` buffer, committing chunks as timestamped `TranscriptSegment`s whenever SFSpeech resets (text shrinks). On stop, the buffered transcript is used directly via `startTranscriptionWithStreamingSegments()` — no WhisperKit batch processing needed. WhisperKit is only used as a fallback when SFSpeech produced no segments. SFSpeech handles 48kHz stereo float32 directly — no resampling needed. WhisperKit no longer loads during recording (~1.5GB RAM saved). `StreamingTranscriber.swift` left in place but unused.
- **SFSpeech session restart** — Apple's `SFSpeechRecognizer` times out after ~60 seconds (error 209). `SpeechStreamingTranscriber` handles this with a `sessionID` counter and `textBuffer`/`sessionLatest` pattern: confirmed text accumulates in `textBuffer`, each new session adds to `sessionLatest`, and callbacks from stale sessions are ignored. `AtomicReference<T>` (NSLock-protected box) gives `nonisolated appendBuffer` thread-safe access to the current `SFSpeechAudioBufferRecognitionRequest`.
- **SFSpeech authorization is lazy** — `SFSpeechRecognizer.requestAuthorization()` is called in `startRecording()` only when status is `.notDetermined`, not at app launch. This prevents a permission dialog loop during the Screen Recording grant-and-restart flow. If denied, recording works normally without live text.
- **`speechRecognitionOnDeviceOnly` setting** — `requiresOnDeviceRecognition = true` by default, persisted in UserDefaults. Toggle in Settings under Audio section.
- **No mobile** — iOS cannot tap into other apps' audio (sandboxing). A mobile version would be a fundamentally different product.
- **App Sandbox disabled** — required for ScreenCaptureKit system audio capture.

## Conventions

- No `fatalError` in production paths — use `guard`/`throw` with descriptive errors
- `@MainActor` for all UI state
- Weak self in all audio callbacks to prevent retain cycles
- Settings window uses hide (`orderOut`) instead of close — avoids NSHostingView teardown crashes
- Use `Task.detached` for long-running downloads (WhisperKit models) to avoid autorelease pool corruption on @MainActor
