# Butler

Butler is a real-time, privacy-first meeting assistant for macOS that runs entirely locally. It uses Apple's native APIs (`AVFoundation`, `ScreenCaptureKit`) alongside state-of-the-art quantized C++ engines (`whisper.cpp`, `llama.cpp`) to listen to your meetings, transcribe speech, evaluate intent in real-time using an LLM, and provide instantaneous AI answers directly on your screen.

**Zero data leaves your machine.**

## Architecture Overview

```mermaid
graph TD
    %% Styling (Light & Clean)
    classDef native fill:#e0f7fa,stroke:none,stroke-width:0px,color:#006064
    classDef engine fill:#ffebee,stroke:none,stroke-width:0px,color:#b71c1c
    classDef logic fill:#e8f5e9,stroke:none,stroke-width:0px,color:#1b5e20
    classDef ui fill:#f3e5f5,stroke:none,stroke-width:0px,color:#4a148c

    Mic["Microphone\n(AVAudioEngine)"]:::native
    SysAudio["System Audio\n(ScreenCaptureKit)"]:::native
    RingBuffer[("Audio Ring Buffer\n(Lock-free)")]:::logic

    VAD{"VAD Gate\n(RMS Threshold)"}:::logic
    Whisper["Whisper.cpp\n(Metal Accelerated)"]:::engine
    Context["Context Manager\n(Conversation History)"]:::logic

    Intent{"Response Generator\n(Intent Evaluation)"}:::logic
    Llama["Llama.cpp\n(Qwen2.5-VL-7B Q4_K_M)"]:::engine
    Mmproj["Vision Projector\n(mmproj f16)"]:::engine

    Overlay["SwiftUI Overlay\n(@MainActor)"]:::ui

    Mic --> RingBuffer
    SysAudio --> RingBuffer
    RingBuffer --> VAD
    VAD -- "Speech Detected" --> Whisper
    Whisper -- "Transcripts" --> Context
    Whisper -- "Segments" --> Intent
    Context --> Intent
    Intent -- "Intent Confirmed (YES)" --> Llama
    Mmproj --> Llama
    Llama -- "Token Stream" --> Overlay
```

## Requirements
- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 14.0 (Sonoma) or newer
- Xcode 15+ 

## Setup
1. Clone the repository and initialize submodules:
   ```bash
   git clone --recursive https://github.com/BGYKanishka/butler.git
   ```
2. Run the bootstrap script to compile `whisper.cpp` and `llama.cpp` for Metal acceleration:
   ```bash
   cd butler
   ./Scripts/bootstrap.sh
   ```
   *(Note: The bootstrap script will automatically run `download_models.sh` to download the necessary Whisper and Llama/Qwen models.)*
   
3. Open the project and build:
   ```bash
   open butler.xcodeproj
   ```
   *(Note: You can also use `xcodegen generate` if needed, which the bootstrap script already handles.)*

## Usage
- Press `Option + Command + Space` anywhere to start/stop listening.
- Press `Option + Command + A` to toggle the AI floating overlay.
- Navigate to the Menu Bar icon to access Preferences, where you can select your microphone, tune the AI temperature, choose the model profile (Fast / Balanced / Quality — these adjust inference parameters such as temperature, max tokens, and thread count, all using the same `Qwen2.5-VL-7B Q4_K_M` model), and manage privacy settings.

## Permissions
On the first run, Butler will request Microphone and Screen Recording permissions. These are required to capture your voice and the system audio (from Zoom/Teams/Meet). No audio is saved to disk unless explicitly enabled in Preferences.
