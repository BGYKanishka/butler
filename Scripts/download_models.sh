#!/bin/bash
set -e

# Download Qwen2.5-VL-7B-Instruct GGUF model
# The model will be placed in the Application Support directory

APP_SUPPORT_DIR="$HOME/Library/Application Support/butler/Models/llm"
MODEL_URL="https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
MODEL_NAME="Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"

MMPROJ_URL="https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf"
MMPROJ_NAME="mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf"

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
