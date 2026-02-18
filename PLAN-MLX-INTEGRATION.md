# Plan: Add MLX Swift as Built-in Summarization Engine

## Context

Currently NoteTaker requires users to install and run Ollama separately for meeting summarization. This adds friction — users must install a separate app, run it in the terminal, and pull models manually. By integrating mlx-swift-lm directly, we can offer a "just works" built-in summarization option that downloads models from Hugging Face (no account needed) and runs inference natively on Apple Silicon.

The user will choose between "Built-in (MLX)" and "Ollama" via a toggle in settings. The model list below changes based on the selection.

## Steps Overview

- [ ] **Step 1:** Add mlx-swift-lm package dependency and verify build
- [ ] **Step 2:** Create MLXModelManager (model list, download, selection)
- [ ] **Step 3:** Create MLXClient (inference wrapper)
- [ ] **Step 4:** Modify SummarizationService to support both backends
- [ ] **Step 5:** Update SummarizationError with MLX-specific errors
- [ ] **Step 6:** Update AppState (backend setting, MLX model selection, auto-summarize logic)
- [ ] **Step 7:** Update ModelPickerView (backend toggle, MLX model download UI)
- [ ] **Step 8:** Update SettingsWindowController (pass MLXModelManager)

---

## Step 1: Add mlx-swift-lm package dependency

**Files:** `project.yml`

In `project.yml`, add to `packages`:
```yaml
packages:
  WhisperKit:
    url: https://github.com/argmaxinc/WhisperKit.git
    from: "0.15.0"
  GRDB:
    url: https://github.com/groue/GRDB.swift.git
    from: "7.0.0"
  MLXSwiftLM:
    url: https://github.com/ml-explore/mlx-swift-lm.git
    from: "1.0.0"
```

And in target dependencies:
```yaml
dependencies:
  - package: WhisperKit
  - package: GRDB
  - package: MLXSwiftLM
    product: MLXLLM
```

Then run `xcodegen generate` and `xcodebuild build` to verify it compiles.

**Verify:** Clean build with no errors.

---

## Step 2: Create MLXModelManager

**Files:** `Sources/Summarization/MLXModelManager.swift` (NEW)

Follows the same pattern as `Sources/Transcription/ModelManager.swift` (WhisperKit model manager).

### Model struct
```swift
struct MLXModel: Identifiable {
    let id: String           // HuggingFace model ID e.g. "mlx-community/Llama-3.2-3B-Instruct-4bit"
    let displayName: String  // e.g. "Llama 3.2 3B"
    let description: String  // e.g. "Good balance of speed and quality"
    let sizeLabel: String    // e.g. "~2 GB"
    let ramRequired: String  // e.g. "~4 GB RAM"
    var isDownloaded: Bool = false
}
```

### MLXModelManager class
```swift
@MainActor
final class MLXModelManager: ObservableObject {
    @Published var models: [MLXModel] = [/* curated list */]
    @Published var selectedModelId: String?
    @Published var downloadProgress: Double = 0
    @Published var downloadingModelId: String?

    private static let selectedModelKey = "selectedMLXModel"
}
```

### Curated model list (all ungated, mlx-community):
| Model | HF ID | Size | RAM |
|-------|--------|------|-----|
| Llama 3.2 3B | `mlx-community/Llama-3.2-3B-Instruct-4bit` | ~2 GB | ~4 GB |
| Qwen 2.5 7B | `mlx-community/Qwen2.5-7B-Instruct-4bit` | ~4 GB | ~8 GB |
| Mistral 7B v0.3 | `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | ~4 GB | ~8 GB |

### Key methods:
- `selectModel(_ id: String)` — persist to UserDefaults
- `downloadModelDetached(_ id:, onProgress:, onComplete:)` — uses `Task.detached` to avoid main thread autorelease pool flooding. Uses `LLMModelFactory.shared.loadContainer(configuration:progressHandler:)` for download.
- `refreshDownloadStatus()` — check HuggingFace Hub cache for already-downloaded models
- `modelIsDownloaded(_ id: String) -> Bool` — check cache

### Important patterns (from WhisperKit ModelManager):
- Download in `Task.detached` via `nonisolated` method
- Progress/completion via closures (not @Published) to avoid layout recursion
- UI uses local `@State` for progress, defers `@Published` updates to next runloop

**Verify:** Unit-level — instantiate manager, confirm model list populated.

---

## Step 3: Create MLXClient

**Files:** `Sources/Summarization/MLXClient.swift` (NEW)

Parallel to `Sources/Summarization/OllamaClient.swift` but using mlx-swift-lm.

### Class structure:
```swift
@MainActor
final class MLXClient {
    private var container: ModelContainer?
    private var loadedModelId: String?

    func loadModel(id: String, onProgress: @escaping (Double) -> Void) async throws
    func chat(systemPrompt: String, userMessage: String) async throws -> String
    func unloadModel()
    var isModelLoaded: Bool { container != nil }
}
```

### loadModel implementation:
- Create `ModelConfiguration(id: modelId)`
- Call `LLMModelFactory.shared.loadContainer(configuration:progressHandler:)` in a detached task
- Store the resulting `ModelContainer`

### chat implementation:
- Use `container.perform { context in ... }` with:
  - `UserInput` constructed from system prompt + user message
  - `GenerateParameters(maxTokens: 4000, temperature: 0.6)`
  - Return `result.output` as String
- Alternatively, use `ChatSession` for simpler API:
  ```swift
  let session = ChatSession(container)
  return try await session.respond(to: fullPrompt)
  ```

### Key design decisions:
- Keep the model loaded in memory after first inference (avoids re-loading each time)
- `unloadModel()` sets container to nil — called when switching backends or on memory pressure
- Same message format as OllamaClient (system prompt + user transcript)

**Verify:** Load a small model, send a test prompt, get a response.

---

## Step 4: Modify SummarizationService

**Files:** `Sources/Summarization/SummarizationService.swift`

### Add backend enum:
```swift
enum SummarizationBackend: String {
    case mlx
    case ollama
}
```

### Add MLX client:
```swift
@MainActor
final class SummarizationService: ObservableObject {
    // Existing
    private(set) var ollamaClient: OllamaClient
    var selectedModel: String?

    // New
    let mlxClient = MLXClient()
    var backend: SummarizationBackend = .mlx
    var selectedMLXModelId: String?
}
```

### Modify summarize():
Branch on `backend`:

**Ollama path** — unchanged (existing code).

**MLX path:**
1. Validate `selectedMLXModelId` is set
2. Load model if not already loaded (with progress updates)
3. Build system prompt (reuse existing `buildSystemPrompt()`)
4. Call `mlxClient.chat(systemPrompt:userMessage:)`
5. Parse response with existing `parseSummary()` — completely reusable

The prompt building and JSON parsing logic is already backend-agnostic — no changes needed there.

**Verify:** Call `summarize()` with backend=.mlx, confirm it produces a valid MeetingSummary.

---

## Step 5: Update SummarizationError

**Files:** `Sources/Summarization/SummarizationError.swift`

Add new cases:
```swift
case mlxModelNotDownloaded    // "Download a summarization model in Settings."
case mlxModelNotSelected      // "Select a summarization model in Settings."
case mlxLoadFailed(Error)     // "Failed to load the MLX model: ..."
```

**Verify:** Each error has a user-friendly `errorDescription`.

---

## Step 6: Update AppState

**Files:** `Sources/App/AppState.swift`

### New properties:
```swift
@Published var summarizationBackend: String {
    didSet { UserDefaults.standard.set(summarizationBackend, forKey: "summarizationBackend") }
}

@Published var selectedMLXModel: String? {
    didSet {
        if let model = selectedMLXModel {
            UserDefaults.standard.set(model, forKey: "selectedMLXModel")
        } else {
            UserDefaults.standard.removeObject(forKey: "selectedMLXModel")
        }
    }
}

let mlxModelManager: MLXModelManager
```

### Default backend: `"mlx"` (built-in is the zero-friction default for new users)

### init() additions:
```swift
mlxModelManager = MLXModelManager()
summarizationBackend = UserDefaults.standard.string(forKey: "summarizationBackend") ?? "mlx"
selectedMLXModel = UserDefaults.standard.string(forKey: "selectedMLXModel")
```

### Modify startSummarization():
```swift
func startSummarization(audio: CapturedAudio, transcription: MeetingTranscription) {
    if summarizationBackend == "mlx" {
        guard let modelId = selectedMLXModel else {
            phase = .error(SummarizationError.mlxModelNotSelected.localizedDescription)
            return
        }
        summarizationService.backend = .mlx
        summarizationService.selectedMLXModelId = modelId
    } else {
        guard let model = selectedOllamaModel else { ... }
        summarizationService.backend = .ollama
        summarizationService.selectedModel = model
    }
    // ... rest is the same (phase = .summarizing, call summarize(), etc.)
}
```

### Modify auto-summarize trigger (in startTranscription):
```swift
// After transcription completes:
if summarizationBackend == "mlx" {
    if selectedMLXModel != nil, mlxModelManager.modelIsDownloaded(selectedMLXModel!) {
        startSummarization(audio: audio, transcription: result)
    }
} else if summarizationBackend == "ollama" {
    if selectedOllamaModel != nil {
        let available = await summarizationService.ollamaClient.checkAvailability()
        if available {
            startSummarization(audio: audio, transcription: result)
        }
    }
}
```

**Verify:** Backend selection persists across restarts. Auto-summarize triggers correctly for both backends.

---

## Step 7: Update ModelPickerView

**Files:** `Sources/Views/ModelPickerView.swift`

### Rename "Ollama" section to "Summarization"

### Add backend picker at top of section:
```swift
Picker("Engine", selection: $appState.summarizationBackend) {
    Text("Built-in (MLX)").tag("mlx")
    Text("Ollama").tag("ollama")
}
.pickerStyle(.segmented)
```

### When "Built-in (MLX)" selected:
Show curated model list (same visual pattern as WhisperKit model section):
- Per-model row: display name, size, RAM requirement
- States: "Download" button / downloading with progress bar / "Select" button / "Selected" (green)
- Uses local `@State` for downloadProgress and downloadingId
- Calls `mlxModelManager.downloadModelDetached()` with closures
- Defers `@Published` updates to next runloop (same pattern as WhisperKit downloads)

### When "Ollama" selected:
Show existing Ollama UI unchanged (server URL, model list, etc.)

### New properties needed:
```swift
@ObservedObject var mlxModelManager: MLXModelManager
@State private var mlxDownloadingId: String?
@State private var mlxDownloadProgress: Double = 0
@State private var mlxDownloadError: String?
```

**Verify:** Toggle between backends, download an MLX model, select it, verify UI updates correctly.

---

## Step 8: Update SettingsWindowController

**Files:** `Sources/App/SettingsWindowController.swift`

Pass `mlxModelManager` from `appState` to `ModelPickerView`:
```swift
ModelPickerView(
    appState: appState,
    modelManager: appState.modelManager,
    audioDeviceManager: appState.audioDeviceManager,
    mlxModelManager: appState.mlxModelManager,  // NEW
    onDismiss: { ... },
    onModelReady: { ... }
)
```

**Verify:** Settings window opens, MLX model manager is accessible in the view.

---

## End-to-End Verification

1. `xcodegen generate && xcodebuild -project NoteTaker.xcodeproj -scheme NoteTaker build`
2. Open Settings → verify "Summarization" section has engine toggle
3. Select "Built-in (MLX)" → see model list → download Llama 3.2 3B
4. Select the downloaded model → close settings
5. Record a short meeting → stop → transcription runs → auto-summarize triggers with MLX
6. Verify summary displays correctly in SummaryResultView
7. Switch to "Ollama" in settings → verify Ollama flow still works
8. Restart app → verify all selections persist

## Notes

- MLX models download from Hugging Face — no account needed (all curated models are ungated)
- Models stored in HuggingFace Hub default cache (`~/.cache/huggingface/hub/`)
- Download sizes: 2-4 GB per model
- MLX runs inference on Apple Silicon GPU — fast on M1+, excellent on M2 Pro+
- Memory: model stays loaded after first use for fast re-summarization; freed on backend switch
