#!/bin/bash
set -e

echo "Running Benchmarks for butler..."

echo "1. llama.cpp bench:"
Vendor/llama.cpp/build/bin/llama-bench -p 512 -n 128

echo "2. whisper.cpp bench:"
Vendor/whisper.cpp/build/bin/whisper-bench

echo "Benchmarks complete!"
