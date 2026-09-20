import Foundation

class WhisperEngine: SpeechToTextEngine {
    private var wrapper: WhisperWrapper?
    private var isLoaded = false
    
    func load() async throws {
        guard !isLoaded else { return }
        
        let fileManager = FileManager.default
        
        let modelPath: String
        let customPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
        
        if !customPath.isEmpty {
            modelPath = customPath
        } else {
            let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            modelPath = appSupportURL.appendingPathComponent("butler/Models/whisper/ggml-base.en.bin").path
        }
        
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
    
    func transcribe(samples: [Float], sampleRate: Int, source: AudioSource) async throws {
        guard let wrapper = wrapper else { return }
        
        // Convert Float array to NSNumber array for Obj-C++ bridging
        let nsSamples = samples.map { NSNumber(value: $0) }
        
        let result = wrapper.transcribeAudio(nsSamples)
        
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
