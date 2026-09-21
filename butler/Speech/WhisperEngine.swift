import Foundation

class WhisperEngine: SpeechToTextEngine {
    private var wrapper: WhisperWrapper?
    private var isLoaded = false
    private let transcriptionQueue = DispatchQueue(label: "com.butler.whisperQueue")
    
    func load() async throws {
        guard !isLoaded else { return }
        
        let fileManager = FileManager.default
        let modelPath = WhisperConfiguration().getModelPath()
        
        // Ensure path exists before initializing C++ context
        guard fileManager.fileExists(atPath: modelPath) else {
            throw AssistantError.modelNotFound("Model not found at \(modelPath)")
        }
        
        wrapper = WhisperWrapper(modelPath: modelPath)
        guard wrapper != nil else {
            throw AssistantError.modelNotFound("Failed to initialize whisper context with model: \(modelPath)")
        }
        
        isLoaded = true
    }
    
    func unload() {
        wrapper = nil // ARC will call dealloc which calls whisper_free()
        isLoaded = false
    }
    
    var onTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    var onPartialTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    
    func transcribe(samples: [Float], sampleRate: Int, source: AudioSource) async throws {
        guard let wrapper = wrapper else { return }
        guard !samples.isEmpty else { return }
        
        let result: String? = await withCheckedContinuation { continuation in
            transcriptionQueue.async {
                wrapper.onPartialTranscript = { [weak self] partialText in
                    let text = partialText
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    let segment = TranscriptSegment(
                        id: UUID(),
                        source: source,
                        startTime: Date().timeIntervalSince1970,
                        endTime: Date().timeIntervalSince1970 + Double(samples.count) / Double(sampleRate),
                        text: text,
                        isFinal: false,
                        confidence: 1.0
                    )
                    self?.onPartialTranscriptionCompleted?(segment)
                }
                
                let text = samples.withUnsafeBufferPointer { ptr in
                    wrapper.transcribeAudio(ptr.baseAddress!, count: samples.count)
                }
                continuation.resume(returning: text)
            }
        }
        
        if let text = result, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let segment = TranscriptSegment(
                id: UUID(),
                source: source,
                startTime: Date().timeIntervalSince1970, // Approximated
                endTime: Date().timeIntervalSince1970 + Double(samples.count) / Double(sampleRate),
                text: text,
                isFinal: true,
                confidence: 1.0
            )
            onTranscriptionCompleted?(segment)
            print("Whisper transcribed: \(text)")
        }
    }
    
    func cancel() {
        wrapper?.cancelTranscription()
    }
}
