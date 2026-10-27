#!/bin/bash
set -e

# Directory paths
DIR="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORKS_DIR="$DIR/Frameworks"
TEMP_DIR="$(mktemp -d)"

trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Packaging XCFrameworks..."

mkdir -p "$FRAMEWORKS_DIR"

# 1. whisper.xcframework
echo "Creating whisper.xcframework..."
mkdir -p "$TEMP_DIR/whisper_headers"
cp "$DIR/Vendor/whisper.cpp/include/whisper.h" "$TEMP_DIR/whisper_headers/"

rm -rf "$FRAMEWORKS_DIR/whisper.xcframework"
xcodebuild -create-xcframework \
  -library "$DIR/Vendor/whisper.cpp/build/src/libwhisper.a" \
  -headers "$TEMP_DIR/whisper_headers" \
  -output "$FRAMEWORKS_DIR/whisper.xcframework"

# 2. llama.xcframework
echo "Creating llama.xcframework..."
mkdir -p "$TEMP_DIR/llama_headers"
cp "$DIR"/Vendor/llama.cpp/include/*.h "$TEMP_DIR/llama_headers/"
cp "$DIR"/Vendor/llama.cpp/ggml/include/*.h "$TEMP_DIR/llama_headers/"
cp "$DIR"/Vendor/llama.cpp/tools/mtmd/*.h "$TEMP_DIR/llama_headers/"

libtool -static -o "$TEMP_DIR/libllama_unified.a" \
  "$DIR/Vendor/llama.cpp/build/src/libllama.a" \
  "$DIR/Vendor/llama.cpp/build/tools/mtmd/libmtmd.a" \
  "$DIR/Vendor/llama.cpp/build/vendor/hash/libvendor-hash.a" \
  "$DIR/Vendor/llama.cpp/build/ggml/src/libggml.a" \
  "$DIR/Vendor/llama.cpp/build/ggml/src/libggml-base.a" \
  "$DIR/Vendor/llama.cpp/build/ggml/src/libggml-cpu.a" \
  "$DIR/Vendor/llama.cpp/build/ggml/src/ggml-metal/libggml-metal.a" \
  "$DIR/Vendor/llama.cpp/build/ggml/src/ggml-blas/libggml-blas.a"

rm -rf "$FRAMEWORKS_DIR/llama.xcframework"
xcodebuild -create-xcframework \
  -library "$TEMP_DIR/libllama_unified.a" \
  -headers "$TEMP_DIR/llama_headers" \
  -output "$FRAMEWORKS_DIR/llama.xcframework"

echo "XCFrameworks generated successfully in $FRAMEWORKS_DIR!"
