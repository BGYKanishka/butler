# Vision Roadmap (v2.0)

Version 1.0 of Butler focuses strictly on audio intelligence. Version 2.0 will introduce contextual screen awareness using `ScreenCaptureKit` and Vision Language Models (VLM).

## The Goal
Butler will be able to answer questions about what is actively being shared on screen during a meeting (e.g. "What does that diagram mean?", "Can you summarize the slide?", "Is there a bug in the code being presented?").

## Planned Architecture

### 1. Frame Sampling (`FrameSampler.swift`)
- Use `ScreenCaptureKit` to grab 1 frame per second.
- Downscale frames to 720p to preserve memory.

### 2. Change Detection (`ChangeDetector.swift`)
- Compare pixel differences between the current frame and the previous frame.
- If delta > 15%, classify as a "New Slide" or "Significant Change".
- Discard duplicate/static frames to avoid drowning the LLM context window.

### 3. OCR & Understanding (`VisionEngine.swift`)
- Pass the changed frame through Apple's native `Vision` framework (VNRecognizeTextRequest) for fast text extraction.
- For complex diagrams or UI elements, pass the frame into our default multimodal LLM (`Qwen2.5-VL`) via the `mmproj` vision projector.

### 4. Trigger Policies (`VisionTriggerPolicy.swift`)
- Vision inference is extremely heavy. We cannot stream video into the LLM at 30fps.
- Frames are stored in a rolling buffer (last 10 seconds).
- When a user asks a question containing spatial keywords ("this", "that", "on screen", "slide"), the `VisionTriggerPolicy` intercepts the NLP pipeline and injects the most recent significant frame into the LLM prompt.

## Integration Challenges
- Memory pressure: Loading the `mmproj` projector requires an additional ~1.5 GB of RAM.
- Core conflicts: `ggml` executing vision projection simultaneously with audio transcription can cause thermal throttling. Strict queue isolation will be required.
