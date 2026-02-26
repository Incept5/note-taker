---
title: Privacy Policy
---

# NoteTaker Privacy Policy

**Last updated:** February 26, 2026

NoteTaker is a macOS application for meeting transcription and summarization. It is built by Incept5 and designed to keep your data private by processing everything locally on your device.

## Data Processing

All audio capture, transcription, and summarization happens entirely on your Mac. No audio, transcripts, or summaries are transmitted to any external server. NoteTaker does not have a backend service, cloud infrastructure, or analytics platform.

## Audio Recordings

NoteTaker captures system audio and optionally microphone input during meetings. Recordings are stored locally on your Mac in the Application Support directory. You can configure automatic deletion of recordings after a retention period (7 to 90 days) in Settings. You can also manually delete any recording at any time.

## Transcription and Summarization

Transcription is performed locally using WhisperKit on Apple Silicon. Summarization is performed locally using either MLX or a locally-running Ollama instance. No transcript or summary data leaves your device.

## Google Calendar Access

NoteTaker requests read-only access to your Google Calendar events (`calendar.events.readonly` scope) to identify meeting participants when a recording starts. This is used to:

- Match the current recording to a calendar event
- Include participant names in meeting summaries

**What we access:** Event titles, times, and attendee lists for events occurring around the time you start a recording.

**What we do not access:** Event descriptions, attachments, your full calendar history, or any other Google account data.

**How the data is used:** Participant names are stored locally in the meeting record on your Mac and included in the locally-generated summary. This data is never transmitted to any external server.

**Token storage:** Google OAuth tokens are stored in your Mac's Keychain. You can revoke access at any time by signing out in NoteTaker Settings or by removing NoteTaker from your Google account's third-party app permissions at [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

## Apple Calendar (EventKit) Access

NoteTaker may request access to your local calendars via EventKit to identify meeting participants. This is the same functionality as Google Calendar access but uses calendars synced through macOS System Settings. The same local-only data handling applies.

## Data Storage

All data is stored locally on your Mac:

- **Audio recordings** — Application Support/NoteTaker/recordings/
- **Meeting records** — SQLite database in Application Support/NoteTaker/
- **Settings** — macOS UserDefaults
- **Google OAuth tokens** — macOS Keychain

No data is stored on any server.

## Data Sharing

NoteTaker does not share any data with third parties. There are no analytics, telemetry, crash reporting services, or advertising frameworks in the application.

## Network Requests

NoteTaker makes network requests only for:

- **Google Calendar API** — To fetch calendar events when signed in (read-only)
- **Google OAuth** — To authenticate and refresh access tokens
- **Ollama** — If configured, to communicate with a locally-running Ollama server (defaults to localhost)

No other network requests are made.

## Children's Privacy

NoteTaker is not directed at children under 13 and does not knowingly collect data from children.

## Changes to This Policy

If this policy changes, the updated version will be posted at this URL with a revised date.

## Contact

For questions about this privacy policy, contact: [privacy@incept5.com](mailto:privacy@incept5.com)
