# Installing NoteTaker

## Requirements

- macOS 14.2+ (Sonoma)
- Apple Silicon (M1 minimum, M2 Pro+ recommended)
- 16GB RAM minimum (32GB recommended for LLM summarization)
- [Ollama](https://ollama.ai) installed locally (for summarization)

## Install from DMG

1. Double-click `NoteTaker-1.0.0.dmg`
2. Drag **NoteTaker** to your Applications folder
3. Launch NoteTaker from Applications — it appears as a menu bar icon (no Dock icon)

## First Launch

On first launch, macOS will ask for **Screen Recording** permission. This is required for capturing system audio from apps like Zoom and Teams. Grant the permission in System Settings > Privacy & Security > Screen Recording.

## Setup

1. **WhisperKit model** — Open Settings from the menu bar popover and download a transcription model. Smaller models (tiny, base) are faster; larger models (small, large) are more accurate.
2. **Ollama model** — Install Ollama and pull a model (e.g. `ollama pull llama3.2`). Select it in Settings for automatic summarization after transcription.

## Usage

1. Click the NoteTaker menu bar icon
2. Select an app to capture audio from (e.g. Zoom, Teams, Chrome)
3. Click Record — both system audio and your microphone are captured
4. Click Stop when done — transcription starts automatically
5. After transcription, summarization runs automatically (if configured)
6. View your meeting history from the History tab
