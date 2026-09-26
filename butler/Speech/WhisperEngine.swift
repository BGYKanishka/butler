import Foundation

class WhisperEngine: SpeechToTextEngine, @unchecked Sendable {
    private var wrapper: WhisperWrapper?
    private var isLoaded = false
    private let transcriptionQueue = DispatchQueue(label: "com.butler.whisperQueue")
    private var currentContext: String = ""
    
    func updateContext(_ text: String) {
        self.currentContext = text
    }
    
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
        transcriptionQueue.sync {
            self.wrapper = nil // ARC will call dealloc which calls whisper_free()
            self.isLoaded = false
        }
    }
    
    private func isValidTranscription(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        
        var cleanedText = trimmed
        if let regex = try? NSRegularExpression(pattern: "\\[.*?\\]|\\(.*?\\)", options: []) {
            let range = NSRange(location: 0, length: cleanedText.utf16.count)
            cleanedText = regex.stringByReplacingMatches(in: cleanedText, options: [], range: range, withTemplate: "")
        }
        
        let alphanumeric = CharacterSet.alphanumerics
        if cleanedText.rangeOfCharacter(from: alphanumeric) == nil {
            return false
        }
        
        return true
    }
    
    var onTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    var onPartialTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    
    func transcribe(samples: [Float], sampleRate: Int, source: AudioSource) async throws {
        guard let wrapper = wrapper else { return }
        guard !samples.isEmpty else { return }
        
        let result: String? = await withCheckedContinuation { continuation in
            transcriptionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                wrapper.onPartialTranscript = { [weak self] partialText in
                    guard let self = self else { return }
                    let text = partialText
                    guard self.isValidTranscription(text) else { return }
                    
                    let segment = TranscriptSegment(
                        id: UUID(),
                        source: source,
                        startTime: Date().timeIntervalSince1970,
                        endTime: Date().timeIntervalSince1970 + Double(samples.count) / Double(sampleRate),
                        text: text,
                        isFinal: false,
                        confidence: 1.0
                    )
                    self.onPartialTranscriptionCompleted?(segment)
                }
                
                let text = samples.withUnsafeBufferPointer { ptr in
                    wrapper.initialPrompt = self.currentContext
                    return wrapper.transcribeAudio(ptr.baseAddress!, count: samples.count)
                }
                continuation.resume(returning: text)
            }
        }
        
        print("Whisper raw result: '\(result ?? "nil")'")
        if let text = result, isValidTranscription(text) {
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
            print("Whisper Info: Ignored empty or non-speech transcription.")
        }
    }
    
    func cancel() {
        wrapper?.cancelTranscription()
    }
}

extension WhisperWrapper: @unchecked Sendable {}
