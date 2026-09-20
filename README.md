# Butler (butler)

Butler is a native macOS real-time AI meeting assistant that leverages local, on-device AI models to listen to your meetings and provide real-time, streaming answers.

## Features
- **Local Audio Capture**: Captures microphone (local) and system/meeting audio (remote) separately.
- **On-Device STT**: Uses `whisper.cpp` (Metal GPU accelerated) for real-time transcription.
- **Local LLM**: Uses `llama.cpp` (Metal GPU accelerated) with multimodal support (Qwen2.5-VL-7B).
- **Invisible Overlay**: The streaming answers appear in a floating window that is completely invisible to screen-sharing software (Zoom, Teams, Meet).
- **Privacy First**: Completely offline after the initial model download. Audio is processed locally and never leaves your machine.

## Setup Instructions
1. Install prerequisites: `brew install cmake`
2. Run the model download script: `./Scripts/download_models.sh`
3. Open `butler.xcodeproj` in Xcode.
4. Ensure the target is set to your Mac.
5. Build and run (Cmd + R).

## Architecture
- Swift & SwiftUI for the macOS app layer.
- C++ / Objective-C++ bridging for AI engine integration.
- `AVAudioEngine` & `ScreenCaptureKit` for audio pipelines.
- Circular ring buffers and energy-based VAD (Voice Activity Detection).
