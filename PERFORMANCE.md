# Performance Metrics

RealtimeAssistant uses Metal-accelerated ggml backends.
- Whisper latency should be under 500ms on Apple Silicon.
- Llama token generation should be ~10-20 tokens per second for a 3B parameter model on M1/M2/M3.
- Peak memory usage should remain under 4GB (using quantized Q4_K_M models).

To monitor, check the console output from `PerformanceMonitor`.
