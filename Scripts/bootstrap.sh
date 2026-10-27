#!/bin/bash
set -e

echo "Bootstrapping butler..."

git submodule update --init --recursive --depth 1

echo "Building whisper.cpp..."
Scripts/build_whisper.sh

echo "Building llama.cpp..."
Scripts/build_llama.sh

echo "Packaging XCFrameworks..."
Scripts/package_frameworks.sh

echo "Downloading models..."
Scripts/download_models.sh

echo "Generating Xcode project..."
xcodegen

echo "Bootstrap complete! Open butler.xcodeproj"
