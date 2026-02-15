# Changelog

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
