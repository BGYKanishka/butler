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

4. **Intent Evaluation** (`ResponseGenerator`)
   - Every transcribed segment is sent to the `LocalLLMEngine`.
   - A `PromptBuilder` formats the conversation context and transcript, prompting the model to decide if a response is required (answering with `YES|` or `NO`).
   - If the model determines intent, it seamlessly continues generating the answer in the same stream.

5. **Inference** (`LocalLLMEngine`)
   - Uses `llama.cpp` with a local GGUF model.
   - Text inference currently defaults to the `Qwen2.5-VL-7B-Instruct` model for robust text processing and upcoming multimodal vision capabilities.
   - Multimodal tasks (future V2) will dynamically load the `mmproj` vision projector.
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
