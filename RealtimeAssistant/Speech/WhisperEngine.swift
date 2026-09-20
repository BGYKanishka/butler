import Foundation

class WhisperEngine: SpeechToTextEngine {
    private let wrapper = WhisperWrapper()
    private var isLoaded = false
    
    func load() async throws {
        guard !isLoaded else { return }
        
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let modelURL = appSupportURL.appendingPathComponent("RealtimeAssistant/Models/whisper/ggml-base.en.bin")
        
        do {
            try wrapper.loadModel(modelURL.path)
        } catch {
            throw AssistantError.modelNotFound("Model not found at \(modelURL.path)")
        }
        
        isLoaded = true
    }
    
    func unload() {
        wrapper.unload()
        isLoaded = false
    }
    
    var onTranscriptionCompleted: ((TranscriptSegment) -> Void)?
    
    func transcribe(samples: [Float], sampleRate: Int) async throws {
        let result = wrapper.transcribeSamples(samples, count: samples.count)
        
        if let text = result, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let segment = TranscriptSegment(
                id: UUID(),
                source: .microphone, // Simplified for now
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
        wrapper.cancel()
    }
}
