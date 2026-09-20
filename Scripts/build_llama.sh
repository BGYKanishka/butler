#!/bin/bash
set -e

echo "Building llama.cpp with Metal support..."
cd "$(dirname "$0")/../Vendor/llama.cpp"

export MACOSX_DEPLOYMENT_TARGET=14.0
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk

# Create a build directory
mkdir -p build
cd build

# Configure CMake for Apple Silicon with Metal
/opt/homebrew/bin/cmake -DGGML_METAL=1 \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      ..

# Build the static library
/opt/homebrew/bin/cmake --build . --config Release -j $(sysctl -n hw.ncpu)

echo "llama.cpp built successfully!"
