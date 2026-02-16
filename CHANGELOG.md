# Changelog

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
