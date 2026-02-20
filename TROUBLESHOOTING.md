# Troubleshooting

## Upgrading from a Previous Version

### Screen Recording Permission Issues

NoteTaker v1.1.2 changed how system audio is captured (from Core Audio Taps to ScreenCaptureKit). If you had a previous version installed, macOS may retain stale permission entries that prevent the new version from working correctly.

**Symptoms:**

- NoteTaker keeps asking for Screen Recording permission even though it appears granted
- System audio capture doesn't work (no audio levels shown for system audio)
- The app launches but cannot detect any apps to record from

**Fix:**

1. Open **System Settings > Privacy & Security > Screen & System Audio Recording**
2. Remove NoteTaker from the list entirely (select it and click the **minus** button)
3. Launch NoteTaker — macOS will prompt you to grant permission fresh
4. If NoteTaker does not appear in the prompt automatically, click the **+** button in Screen & System Audio Recording and add NoteTaker manually from your Applications folder
5. Restart NoteTaker after granting permission

### Permission Loop

If you get stuck in a loop where the app keeps asking for permission but System Settings shows it as already granted, the permissions are stale. Remove and re-add NoteTaker as described above.

### macOS Settings Cache

In rare cases, macOS caches permission state aggressively. If removing and re-adding NoteTaker doesn't resolve the issue:

1. Quit NoteTaker
2. Open **Terminal** and run: `tccutil reset ScreenCapture com.incept5.NoteTaker`
3. Relaunch NoteTaker and grant permission when prompted

## Microphone Not Working

If NoteTaker isn't picking up your voice:

1. Check that **Microphone** permission is granted in **System Settings > Privacy & Security > Microphone**
2. If you're using an external microphone, open **Settings** (gear icon) and select your device from the **Microphone Input** section
3. Verify the microphone works in other apps (e.g. Voice Memos)

## Transcription Issues

### Model Not Downloaded

If transcription doesn't start after recording, open **Settings** and check that a WhisperKit model has been downloaded. The first download is ~1.5 GB.

### Transcription Is Slow or Inaccurate

- Larger models (small, large) are more accurate but slower
- Smaller models (tiny, base) are faster but less accurate
- M2 Pro or better is recommended for real-time streaming transcription

## Summarization Issues

### MLX (Default Backend)

- Ensure you've downloaded an MLX model in **Settings**
- First download may take several minutes depending on model size

### Ollama Backend

- Ollama must be running (`ollama serve`) for summarization to work
- Verify Ollama is accessible: `curl http://localhost:11434/api/tags`
- If using a remote Ollama server, check the server URL in **Settings** and ensure the remote machine is reachable on your network

## App Doesn't Appear in Menu Bar

NoteTaker is a menu bar app — it does not show in the Dock. Look for the NoteTaker icon in your menu bar (top-right of the screen). If you have many menu bar items, it may be hidden by the notch on newer MacBooks. Try closing other menu bar apps or using a tool like Bartender to manage overflow.

## Resetting the App

To completely reset NoteTaker to a clean state:

1. Quit NoteTaker
2. Delete app data: `rm -rf ~/Library/Application\ Support/NoteTaker`
3. Reset permissions: `tccutil reset ScreenCapture com.incept5.NoteTaker`
4. Relaunch NoteTaker

This removes all recordings, transcripts, summaries, and settings. You will need to re-download the WhisperKit model and reconfigure your preferences.
