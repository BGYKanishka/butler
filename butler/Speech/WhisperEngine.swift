import Foundation

class WhisperEngine: SpeechToTextEngine, @unchecked Sendable {
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
        guard let wrapper = wrapper else {
            throw AssistantError.modelNotFound("Failed to initialize whisper context with model: \(modelPath)")
        }
        
        // Add context for programming/meeting terminology to improve transcription accuracy
        wrapper.initialPrompt = "Transcript of a software engineering meeting discussing React hooks, programming, variables, functions, and code."
        
        isLoaded = true
    }
    
    func unload() {
        transcriptionQueue.sync {
            self.wrapper = nil // ARC will call dealloc which calls whisper_free()
            self.isLoaded = false
        }
    }
    
    var onTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    var onPartialTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    
    func transcribe(samples: [Float], sampleRate: Int, source: AudioSource) async throws {
        guard let wrapper = wrapper else { return }
        guard !samples.isEmpty else { return }
        
        let result: String? = await withCheckedContinuation { continuation in
            transcriptionQueue.async { [weak self] in
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
        
        print("Whisper raw result: '\(result ?? "nil")'")
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
        } else {
            print("Whisper Info: Ignored empty or whitespace-only transcription.")
        }
    }
    
    func cancel() {
        wrapper?.cancelTranscription()
    }
}

extension WhisperWrapper: @unchecked Sendable {}
