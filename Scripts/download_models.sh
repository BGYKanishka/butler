#!/bin/bash
set -e

APP_SUPPORT_DIR="$HOME/Library/Application Support/butler/Models"
LLM_DIR="$APP_SUPPORT_DIR/llm"
WHISPER_DIR="$APP_SUPPORT_DIR/whisper"

mkdir -p "$LLM_DIR"
mkdir -p "$WHISPER_DIR"

echo "Downloading Whisper Model..."
WHISPER_MODEL="ggml-base.en.bin"
if [ ! -f "$WHISPER_DIR/$WHISPER_MODEL" ]; then
    curl -L -o "$WHISPER_DIR/$WHISPER_MODEL" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"
else
    echo "$WHISPER_MODEL already exists."
fi

echo "Downloading Qwen VL Model..."
MODEL_URL="https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
MODEL_NAME="Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"

if [ ! -f "$LLM_DIR/$MODEL_NAME" ]; then
    curl -L -o "$LLM_DIR/$MODEL_NAME" "$MODEL_URL"
else
    echo "$MODEL_NAME already exists."
fi

echo "Downloading Vision Projector (mmproj)..."
MMPROJ_URL="https://huggingface.co/bartowski/Qwen_Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf"
MMPROJ_NAME="mmproj-Qwen_Qwen2.5-VL-7B-Instruct-f16.gguf"

if [ ! -f "$LLM_DIR/$MMPROJ_NAME" ]; then
    curl -L -o "$LLM_DIR/$MMPROJ_NAME" "$MMPROJ_URL"
else
    echo "$MMPROJ_NAME already exists."
fi

echo "All models downloaded."
