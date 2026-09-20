#!/bin/bash
set -e

echo "Building llama.cpp with Metal support..."
cd "$(dirname "$0")/../Vendor/llama.cpp"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

# Configure with CMake
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DGGML_LTO=OFF \
  -DLLAMA_NATIVE=OFF

# Build using available cores
cmake --build build --config Release -j$(sysctl -n hw.ncpu)

echo "llama.cpp build complete."
