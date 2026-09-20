#!/bin/bash
set -e

# Download Qwen2.5-VL-7B-Instruct GGUF model
# The model will be placed in the Application Support directory

APP_SUPPORT_DIR="$HOME/Library/Application Support/RealtimeAssistant/Models/llm"
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/qwen2.5-vl-7b-instruct-q4_k_m.gguf"
MODEL_NAME="Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"

MMPROJ_URL="https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-qwen2.5-vl-7b-instruct-f16.gguf"
MMPROJ_NAME="mmproj-qwen2.5-vl-7b-instruct-f16.gguf"

mkdir -p "$APP_SUPPORT_DIR"

echo "Downloading LLM Model to $APP_SUPPORT_DIR..."

if [ ! -f "$APP_SUPPORT_DIR/$MODEL_NAME" ]; then
    echo "Downloading $MODEL_NAME..."
    curl -L -o "$APP_SUPPORT_DIR/$MODEL_NAME" "$MODEL_URL"
else
    echo "$MODEL_NAME already exists."
fi

if [ ! -f "$APP_SUPPORT_DIR/$MMPROJ_NAME" ]; then
    echo "Downloading $MMPROJ_NAME (Vision Projector)..."
    curl -L -o "$APP_SUPPORT_DIR/$MMPROJ_NAME" "$MMPROJ_URL"
else
    echo "$MMPROJ_NAME already exists."
fi

echo "All LLM models downloaded."
