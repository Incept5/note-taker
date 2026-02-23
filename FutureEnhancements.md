# Future Enhancements

Planned and aspirational features for Note Taker, roughly in priority order.

---

## 1. Speaker Diarization — Identify Individual Speakers

**Status:** Not yet possible with current dependencies
**Priority:** High
**Complexity:** Significant

### What We Want

True speaker diarization: automatically identifying and labelling individual speakers throughout a transcript (e.g. "Speaker 1", "Speaker 2", or ideally learned names like "Alice", "Bob"). This would replace the current "You" vs "Others" split with a full multi-speaker conversation view.

### Why It's Not Possible Today

Note Taker uses [WhisperKit](https://github.com/argmaxinc/WhisperKit) for on-device transcription. WhisperKit (and the underlying Whisper model) performs speech-to-text only — it has no speaker embedding, voice clustering, or diarization capability. It cannot distinguish between different voices in a single audio stream.

The current "You" / "Others" separation works only because we capture two distinct audio sources:
- **System audio** (ScreenCaptureKit) — captures remote participants
- **Microphone** (AVAudioEngine) — captures the local user

Within the system audio stream, if three remote participants are speaking, WhisperKit has no way to tell them apart. The segments are interleaved chronologically but all labelled "Others".

### What Would Be Needed

To add true diarization, we would need one of the following approaches:

#### Option A: Argmax SpeakerKit (Commercial)

Argmax (the creators of WhisperKit) have released [SpeakerKit](https://www.argmaxinc.com/blog/speakerkit), a companion framework specifically for on-device speaker diarization. It identifies "who spoke when" and is designed to work alongside WhisperKit transcription output.

**Pros:**
- Purpose-built to pair with WhisperKit
- Extremely fast — processes ~4 minutes of audio in ~1 second on iPhone
- Matches state-of-the-art accuracy (benchmarked against Pyannote across 13 datasets)
- Small footprint (~10 MB)
- Supports macOS 13+

**Cons:**
- Commercial product — requires an Argmax Pro SDK subscription licence
- Not open source (only the benchmarking toolkit SDBench is public)
- Would add a paid dependency to an otherwise fully free/local app

#### Option B: Port or Integrate an Open-Source Diarization Model

Projects like [pyannote-audio](https://github.com/pyannote/pyannote-audio) and [WhisperX](https://github.com/m-bain/whisperX) provide open-source speaker diarization, but they are Python-based. Integrating them would require either:

- Converting the pyannote model to Core ML and writing a Swift inference wrapper
- Running a local Python process alongside the app (heavy, poor UX)
- Finding or building a native Swift diarization pipeline from scratch

This is a substantial engineering effort with no off-the-shelf Swift solution currently available.

#### Option C: Apple SpeechAnalyzer (macOS 26 Tahoe)

Apple introduced the [SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/) framework at WWDC 2025, shipping with macOS 26 (Tahoe) and iOS 26. SpeechAnalyzer is a modern replacement for the legacy `SFSpeechRecognizer` API, built with Swift and designed for long-form conversational audio.

**What SpeechAnalyzer brings:**
- On-device speech-to-text with no network requirement
- Word-level timestamps and voice activity detection
- Async/await API with real-time streaming support
- Reported to be ~55% faster than Whisper in benchmarks
- Downloadable models managed by the OS (shared across apps)

**What it does NOT currently include:**
- Speaker diarization — as of the initial release, SpeechAnalyzer does not identify individual speakers. It provides transcription and timestamps only.

However, Apple's investment in on-device speech intelligence (SpeechAnalyzer, the Foundation Models framework, and enhanced Siri) strongly suggests that speaker diarization is on their roadmap. If Apple adds native diarization to SpeechAnalyzer in a future macOS 26.x update or macOS 27, it would be the ideal solution: zero external dependencies, OS-managed models, and tight system integration.

**Our plan:** When macOS 26 reaches stable release and we raise our minimum deployment target, we will evaluate replacing WhisperKit with SpeechAnalyzer for transcription. If Apple adds diarization support, we would adopt it immediately. In the meantime, SpeakerKit remains the most practical path if we decide diarization can't wait.

### Current Workaround

The app currently provides:
- **"You" vs "Others"** labels derived from separate mic and system audio streams
- **Speaker change detection** based on timing gaps (>2 seconds of silence suggests a different person is speaking)
- **10-second paragraph breaks** for readability

This is a reasonable heuristic but does not identify individual remote participants.

---

## 2. (More entries to follow)

*This document will be expanded as future features are scoped and prioritised.*
