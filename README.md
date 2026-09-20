# Realtime Assistant

A native macOS menu bar application providing real-time AI context via local models (whisper.cpp and llama.cpp).

## Requirements
- macOS 14.0+
- Apple Silicon (M1/M2/M3)
- Xcode 15+ (for building)

## Quick Start
1. Run `./Scripts/bootstrap.sh` to fetch models and dependencies.
2. Open `RealtimeAssistant.xcodeproj` and build the project.

## Architecture
See `ARCHITECTURE.md` for a detailed breakdown of the application architecture, including the audio pipeline, AI integrations, and UI overlay.
