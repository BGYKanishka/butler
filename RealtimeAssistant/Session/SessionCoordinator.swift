import Foundation
import Combine

class SessionCoordinator: ObservableObject {
    let micService = MicrophoneCaptureService()
    let sysAudioService = SystemAudioCaptureService()
    let whisperEngine = WhisperEngine()
    let llmEngine = LocalLLMEngine()
    
    let micVAD = VoiceActivityDetector()
    let sysVAD = VoiceActivityDetector()
    let micRingBuffer = AudioRingBuffer(capacity: 16000 * 60)
    let sysRingBuffer = AudioRingBuffer(capacity: 16000 * 60)
    
    let contextManager = ContextManager()
    let promptBuilder = PromptBuilder()
    let questionDetector = QuestionDetector()
    lazy var responseGenerator = ResponseGenerator(contextManager: contextManager, promptBuilder: promptBuilder, llmEngine: llmEngine)
    let transcriptAssembler = TranscriptAssembler()
    
    @Published var overlayViewModel = OverlayViewModel()
    @Published var state: SessionState = .idle
    
    private var speechStartTimestamp: TimeInterval?
    
    init() {
        setupBindings()
    }
    
    private func setupBindings() {
        responseGenerator.onTokenGenerated = { [weak self] token in
            DispatchQueue.main.async {
                self?.overlayViewModel.appendLLMToken(token)
            }
        }
        
        responseGenerator.onResponseCompleted = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self?.overlayViewModel.clearLLMResponse()
                self?.state = .listening
            }
        }
        
        micService.onSamplesCaptured = { [weak self] samples in
            self?.handleMicSamples(samples)
        }
        
        sysAudioService.onSamplesCaptured = { [weak self] samples in
            self?.handleSysSamples(samples)
        }
        
        whisperEngine.onTranscriptionCompleted = { [weak self] segment in
            self?.handleTranscription(segment: segment)
        }
    }
    
    private func handleTranscription(segment: TranscriptSegment) {
        transcriptAssembler.addSegment(segment)
        
        let turn = ConversationTurn(id: UUID(), source: segment.source, text: segment.text, timestamp: Date())
        contextManager.addTurn(turn)
        
        DispatchQueue.main.async {
            self.overlayViewModel.appendSubtitle(segment.text)
        }
        
        let result = questionDetector.detect(transcript: segment.text, source: segment.source)
        if result == .strongQuestion {
            DispatchQueue.main.async {
                self.state = .answering
            }
            responseGenerator.handleQuestionDetected(segment.text)
        } else {
            DispatchQueue.main.async {
                self.state = .listening
            }
        }
    }
    
    private func handleMicSamples(_ samples: [Float]) {
        micRingBuffer.push(samples, timestamp: 0)
        
        // Calculate RMS
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        let timestamp = Date().timeIntervalSince1970
        
        let wasSpeaking = micVAD.process(rms: rms, timestamp: timestamp)
        
        // Trigger Whisper when speech ends
        if wasSpeaking && state == .listening {
            if speechStartTimestamp == nil {
                speechStartTimestamp = timestamp
            }
        } else if !wasSpeaking && speechStartTimestamp != nil {
            // Speech ended
            let duration = timestamp - speechStartTimestamp!
            speechStartTimestamp = nil
            
            if duration > 0.5 { // Only transcribe if > 0.5s
                // Pull samples from ring buffer (e.g. last 'duration' + buffer seconds)
                let sampleCount = Int(duration * 16000)
                let pulledSamples = micRingBuffer.getRecent(samplesCount: sampleCount)
                
                Task {
                    DispatchQueue.main.async {
                        self.state = .processing
                    }
                    try? await self.whisperEngine.transcribe(samples: pulledSamples, sampleRate: 16000)
                }
            }
        }
    }
    
    private func handleSysSamples(_ samples: [Float]) {
        sysRingBuffer.push(samples, timestamp: 0)
        // Similar VAD logic could go here for system audio
    }
    
    func startSession() {
        guard state == .idle else { return }
        state = .listening
        
        Task {
            do {
                try await whisperEngine.load()
                try await llmEngine.load()
                
                try await micService.start()
                try await sysAudioService.start()
                
                print("Session started.")
            } catch {
                print("Failed to start session: \(error)")
                DispatchQueue.main.async {
                    self.state = .idle
                }
            }
        }
    }
    
    func stopSession() {
        guard state != .idle else { return }
        
        micService.stop()
        sysAudioService.stop()
        whisperEngine.cancel()
        llmEngine.cancel()
        
        state = .idle
        print("Session stopped.")
    }
    
    // For testing
    func simulateSpeechDetected(text: String, source: AudioSource) {
        let segment = TranscriptSegment(id: UUID(), source: source, startTime: 0, endTime: 0, text: text, isFinal: true, confidence: 1.0)
        transcriptAssembler.addSegment(segment)
        
        let turn = ConversationTurn(id: UUID(), source: source, text: text, timestamp: Date())
        contextManager.addTurn(turn)
        
        DispatchQueue.main.async {
            self.overlayViewModel.appendSubtitle(text)
        }
        
        let result = questionDetector.detect(transcript: text, source: source)
        if result == .strongQuestion {
            self.state = .answering
            responseGenerator.handleQuestionDetected(text)
        }
    }
}
