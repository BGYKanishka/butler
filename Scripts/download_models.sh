#!/bin/bash
set -e

# Download Whisper model
WHISPER_MODEL="ggml-base.en.bin"
WHISPER_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL"

# Download LLaMA model (Qwen2.5-VL-7B for Multimodal)
LLAMA_MODEL="Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
LLAMA_URL="https://huggingface.co/bartowski/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"

# Download Multimodal projector for vision support (Future-proofing)
MMPROJ_MODEL="mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf"
MMPROJ_URL="https://huggingface.co/bartowski/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf"

# Directories
APP_SUPPORT_DIR="$HOME/Library/Application Support/RealtimeAssistant/Models"
WHISPER_DIR="$APP_SUPPORT_DIR/whisper"
LLAMA_DIR="$APP_SUPPORT_DIR/llama"

mkdir -p "$WHISPER_DIR"
mkdir -p "$LLAMA_DIR"

echo "Downloading Whisper model..."
if [ ! -f "$WHISPER_DIR/$WHISPER_MODEL" ]; then
    curl -L -o "$WHISPER_DIR/$WHISPER_MODEL" "$WHISPER_URL"
else
    echo "Whisper model already exists."
fi

echo "Downloading LLaMA model..."
if [ ! -f "$LLAMA_DIR/$LLAMA_MODEL" ]; then
    curl -L -o "$LLAMA_DIR/$LLAMA_MODEL" "$LLAMA_URL"
else
    echo "LLaMA model already exists."
fi

echo "Downloading Multimodal Projector (vision support)..."
if [ ! -f "$LLAMA_DIR/$MMPROJ_MODEL" ]; then
    curl -L -o "$LLAMA_DIR/$MMPROJ_MODEL" "$MMPROJ_URL"
else
    echo "Multimodal Projector already exists."
fi

echo "Models downloaded successfully!"
