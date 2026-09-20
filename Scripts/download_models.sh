#!/bin/bash
set -e

# Download Whisper model
WHISPER_MODEL="ggml-base.en.bin"
WHISPER_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL"

# Download LLaMA model (tinyllama for quick testing)
LLAMA_MODEL="tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"
LLAMA_URL="https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf"

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

echo "Models downloaded successfully!"
