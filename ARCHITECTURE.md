# Architecture

Butler is built with a strictly unidirectional, asynchronous pipeline designed for ultra-low latency inference on Apple Silicon.

## The Pipeline

1. **Audio Capture** (`MicrophoneCaptureService`, `SystemAudioCaptureService`)
   - Captures raw audio via `AVAudioEngine` and `ScreenCaptureKit`.
   - Normalizes audio to 16kHz Float32 mono.
   - Pushes samples to the lock-free `AudioRingBuffer`.

2. **Voice Activity Detection (VAD)**
   - Monitors the RMS level of the audio stream.
   - Gating mechanism prevents sending background noise to the speech engine.
   - Triggers `WhisperEngine` transcription only when sustained speech is detected.

3. **Transcription** (`WhisperEngine`)
   - Uses `whisper.cpp` with Metal acceleration.
   - Assembles text segments using `TranscriptAssembler` to handle stutters and mid-sentence corrections.

4. **Transcript Correction & Dual-Purpose Vocabulary** (`TranscriptCorrector`)
   - Uses domain terms extracted from the project codebase to correct speech recognition errors in real time (e.g. "frag system" -> "RAG system").
   - Keeps vocabulary synchronized with the active project.

5. **Code Context Retrieval & RAG** (`HybridProjectRetriever`, `ProjectIndexCoordinator`, `ContextAssembler`)
   - SQLite FTS5 database stores indexed repository code, symbol definitions, and AST signatures.
   - On every query, runs a hybrid search combining full-text FTS5 matching and exact symbol lookup.
   - Constrained by a strict 250ms race budget: if retrieval takes longer, the pipeline falls back gracefully to answering without code context to never stall real-time speech.
   - `ContextAssembler` formats relevant file snippets with line numbers into token-budgeted prompt sections.

6. **Intent Evaluation & Inference** (`ResponseGenerator`, `LocalLLMEngine`)
   - Every transcribed segment is sent to `ResponseGenerator`.
   - `PromptBuilder` formats conversation turns, project summaries, retrieved code snippets, and current query.
   - Prompt is evaluated by `llama.cpp` using local quantized GGUF weights (`Qwen2.5-VL-7B-Instruct`).
   - Binary KV cache state caching (`saveState`/`loadState`) preserves static project prefixes, eliminating initial evaluation latency.
   - For multimodal visual queries, the `mmproj` vision projector is dynamically bound.
   - Streams tokens directly to UI via callbacks with active `RepetitionGuard` protection.

7. **UI Rendering**
   - Built with SwiftUI.
   - Follows `@MainActor` isolation.
   - Uses `NSWindow.SharingType.none` to remain invisible to screen recording tools.

## Threading Rules
- **Audio Thread:** Real-time priority. Never block. Use `os_unfair_lock` for ring buffers. No `DispatchQueue.sync`.
- **Inference Threads:** Managed by `ggml`. Heavy work is dispatched to background `Task.detached`.
- **UI Thread:** Only accepts lightweight `@Published` updates.
