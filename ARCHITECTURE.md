# Architecture Overview

## Data Pipeline
1. **Audio Capture**: `AVAudioEngine` for microphone and system audio via ScreenCaptureKit.
2. **Buffering**: `AudioRingBuffer` holds the last 15-30 seconds of audio.
3. **VAD**: `VoiceActivityDetector` monitors RMS audio energy to chunk sentences.
4. **Transcription**: `WhisperWrapper` runs whisper.cpp on chunks.
5. **Context**: `ContextManager` maintains the conversation transcript.
6. **Intelligence**: `QuestionDetector` triggers the `LocalLLMEngine` to stream answers.

## Modularity
- **UI**: SwiftUI views hooked to a central `MainCoordinator`.
- **C++/Swift**: Objective-C++ wrappers expose C structs as Swift APIs.
