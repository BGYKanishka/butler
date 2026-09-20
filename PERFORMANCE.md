# Performance

This document outlines the strict performance targets and hardware constraints for Butler.

## Hardware Budget (Apple Silicon M-Series)

Butler is designed to run efficiently in the background without starving primary foreground applications.

- **CPU Budget:** < 5% during idle listening. < 300% (3 cores) during burst transcription/generation.
- **RAM Budget:** ~8 GB baseline. Absolute maximum of 15 GB unified memory. A `MemoryMonitor` runs in the background and will emit OSLog faults if the 15 GB threshold is breached.
- **GPU Budget:** Highly optimized Metal shaders (`ggml-metal`) limit VRAM swapping.

## Latency Targets

We use `os_signpost` to trace pipeline latency. The goal is to provide answers before the user even finishes processing the remote participant's question.

- **Audio Capture to VAD:** < 10ms
- **VAD Trigger to Whisper Start:** < 50ms
- **Whisper Transcription (per segment):** < 400ms (using `ggml-base.en`)
- **Question Detection NLP:** < 5ms
- **LLM Time-To-First-Token (TTFT):** < 800ms
- **LLM Generation Speed:** > 30 tokens/second (using 4-bit quantized Qwen2.5 7B)

Total End-to-End Latency (Speech End -> First Answer Token): **< 1.5 Seconds**

## Bottlenecks & Profiling

If latency spikes occur, use Apple's Instruments app:
1. Open Instruments and attach to `butler`.
2. Select the `os_signpost` template.
3. Filter for `com.example.butler` subsystem to view the waterfall graph of audio chunks hitting the LLM.
