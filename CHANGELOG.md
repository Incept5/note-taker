# Changelog

## 1.1.2

- **Fixed system audio capture** — Replaced Core Audio Taps with ScreenCaptureKit for reliable system audio recording. The previous approach (`AudioHardwareCreateProcessTap`) delivered silent `system.wav` files in many configurations — Bluetooth output, stale TCC entries, and permission edge cases. Now uses ScreenCaptureKit `SCStream` in audio-only mode, which works reliably across all output devices.
- **Works without microphone** — Recording now works even when there is no microphone input connected.
- **Upgrade note** — If upgrading from a previous version, remove NoteTaker from **System Settings > Privacy & Security > Screen & System Audio Recording** before launching v1.1.2. Relaunch the app and grant permission when prompted. If NoteTaker doesn't appear in the prompt, add it manually using the **+** button.

## 1.1.1

- **Fixed MLX summary formatting** — Summaries from the MLX backend no longer contain raw JSON artifacts (bracket characters, literal `\n\n` strings, or raw `{"task": ..., "owner": ...}` fragments). Added post-processing cleanup across all parsing paths.

## 1.1.0

- **MLX local summarization** — Summarize meetings using local MLX models directly, removing the need to install and run an Ollama server. MLX is now the default backend.
- **In-app model management** — Browse, download, and manage MLX models from the Settings panel. No terminal commands needed.
- **Backend selector** — Choose between MLX (default) and Ollama in Settings. Ollama remains available for users who prefer it or want to use a remote server.
- **Summary attribution** — The summary view now shows which backend (MLX or Ollama) produced the result.

## 1.0.6

- **External microphone support** — Select your preferred audio input device in Settings. Supports USB microphones, audio interfaces, and other external input devices.
- **Device hot-plug detection** — Automatically detects when audio devices are connected or disconnected, updating the device list in real time.
- **Persistent device selection** — Your chosen microphone is remembered across app restarts. Falls back to the system default if a saved device is no longer available.

## 1.0.5

- **Meeting history window** — History now opens in a dedicated resizable window instead of inline in the popover. Browse a scrollable list of past meetings and click to drill into the detail view with side-by-side summary and transcript.
- **Cleaner transcripts** — Merged system and microphone audio into a single chronological transcript sorted by timestamp. Removed misleading "You"/"Others" speaker labels (Whisper doesn't do speaker diarization). Stripped raw Whisper tokens (`<|startoftranscript|>`, `<|en|>`, timestamps, `<|endoftext|>`) from output.
- **Improved summary layout** — Key Points, Decisions, Action Items, and Open Questions now appear above the full narrative summary. Summary text is rendered with paragraph breaks instead of a single wall of text.
- **Fixed result window crash** — Closing the summary window after summarization no longer crashes the app. Applied the same hide-on-close pattern used by the Settings window.
- **Fixed app launch reliability** — Added a static strong reference to the AppDelegate to prevent ARC from releasing it (NSApplication.delegate is weak).

## 1.0.4

- **Fixed model download crash** — Downloading WhisperKit models from Settings no longer crashes or freezes the app. Downloads now run in a background thread, with progress shown inline next to the model.
- **Improved Settings window stability** — Settings window now hides instead of closing, preventing freezes caused by SwiftUI layout recursion in NSHostingView. The window can be opened and closed freely without affecting the app.

## 1.0.3

- **Remote Ollama server support** — You can now point NoteTaker at a remote Ollama instance instead of localhost. Useful for offloading summarization to a more powerful machine (e.g. a Mac Mini or Studio with 64GB+ RAM running larger models). Configure the server URL in Settings.
- **Settings opens in a dedicated window** — Settings now opens in a proper resizable window instead of being crammed into the menu bar popover, giving more room for model selection and configuration.
- **Quit button** — Added a quit button to the menu bar popover for easy app shutdown.

## 1.0.2

- **Fixed summary formatting** — Summaries from some Ollama models were displaying as raw JSON instead of nicely formatted sections. Improved JSON parsing to handle LLM responses that include preamble text, trailing commentary, or markdown code fences around the JSON output.

## 1.0.1

- **Improved meeting summaries** — Rewrote the summarization prompt to produce much more detailed and comprehensive meeting breakdowns. Summaries now include multi-paragraph overviews, thorough key points with full context, decisions with reasoning, specific action items with deadlines, and expanded open questions covering deferred topics. Someone who missed the meeting should be able to read the summary and understand everything that happened.
- **Recommended model: qwen3-vl** — Updated setup instructions to recommend `qwen3-vl` as the Ollama model, which produces excellent summarization results.

## 1.0.0

- Initial release
- Record microphone and system audio simultaneously (Zoom, Teams, Meet, etc.)
- Local transcription via WhisperKit (Apple Silicon optimized)
- Local summarization via Ollama with structured output (overview, key points, decisions, action items, open questions)
- Meeting history with SQLite persistence
- Copy buttons for summary (markdown) and raw transcript
- Menu bar app — no Dock icon, no main window
- Zero network calls — fully offline pipeline
