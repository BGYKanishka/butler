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

4. **Question Detection** (`QuestionDetector`)
   - Fast, heuristics-based NLP checks if the final transcript segment ends in a question mark, contains interrogative keywords ("what", "how", "why"), or has rising intonation markers.
   - If a question is detected from a REMOTE source, it triggers the LLM.

5. **Inference** (`LocalLLMEngine`)
   - Uses `llama.cpp` with a local GGUF model.
   - Text inference uses `Llama-3.2-3B-Instruct.gguf` by default for performance and RAM constraints.
   - Multimodal tasks (future V2) will dynamically load `Qwen2.5-VL`.
   - Injected with conversation history via `ContextManager`.
   - Streams tokens via callbacks to the UI thread.

6. **UI Rendering**
   - Built with SwiftUI.
   - Follows `@MainActor` isolation.
   - Uses `NSWindow.SharingType.none` to remain invisible to screen recording tools.

## Threading Rules
- **Audio Thread:** Real-time priority. Never block. Use `os_unfair_lock` for ring buffers. No `DispatchQueue.sync`.
- **Inference Threads:** Managed by `ggml`. Heavy work is dispatched to background `Task.detached`.
- **UI Thread:** Only accepts lightweight `@Published` updates.
