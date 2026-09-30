import Foundation

// MARK: - FutureVision Module (Not Yet Implemented)
//
// These protocols define the intended interface for the upcoming
// real-time vision pipeline. Implementations will be added in a future sprint.
// All stubs are consolidated here to avoid compile-time noise from
// six separate placeholder files.

protocol ChangeDetector {
    // Detects meaningful visual changes between consecutive frames.
}

protocol VisionEngine {
    // Orchestrates frame capture, change detection, and OCR.
}

protocol OCRService {
    // Extracts text from captured screen regions.
}

protocol FrameSampler {
    // Samples frames from the screen at a defined rate.
}

protocol VisionTriggerPolicy {
    // Decides when to trigger a vision analysis pass.
}

protocol ScreenCaptureServiceProtocol {
    // Abstracts the underlying screen capture mechanism (SCStream etc.).
}
