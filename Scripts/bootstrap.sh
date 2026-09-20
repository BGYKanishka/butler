#!/bin/bash
set -e

echo "Bootstrapping RealtimeAssistant..."

git submodule update --init --recursive --depth 1

echo "Building whisper.cpp..."
Scripts/build_whisper.sh

echo "Building llama.cpp..."
Scripts/build_llama.sh

echo "Downloading models..."
Scripts/download_models.sh

echo "Generating Xcode project..."
xcodegen

echo "Bootstrap complete! Open RealtimeAssistant.xcodeproj"
