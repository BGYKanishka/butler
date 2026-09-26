#!/bin/bash
set -e

echo "Fetching latest upstream changes for llama.cpp and whisper.cpp..."

# Update submodules to their latest remote commits
git submodule update --remote --merge

echo "Rebuilding whisper.cpp..."
Scripts/build_whisper.sh

echo "Rebuilding llama.cpp..."
Scripts/build_llama.sh

echo "Engines updated and rebuilt successfully!"
