import Foundation
import Combine

class MainCoordinator: ObservableObject {
    let micService = MicrophoneCaptureService()
    let sysAudioService = SystemAudioCaptureService()
    let whisperEngine = WhisperEngine()
    let llmEngine = LocalLLMEngine()
    
    let micVAD = VoiceActivityDetector()
    let sysVAD = VoiceActivityDetector()
    let micRingBuffer = AudioRingBuffer()
    let sysRingBuffer = AudioRingBuffer()
    
    let contextManager = ContextManager()
    let promptBuilder = PromptBuilder()
    let questionDetector = QuestionDetector()
    lazy var responseGenerator = ResponseGenerator(contextManager: contextManager, promptBuilder: promptBuilder, llmEngine: llmEngine)
    let transcriptAssembler = TranscriptAssembler()
    
    @Published var overlayViewModel = OverlayViewModel()
    @Published var isRunning = false
    
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
            }
        }
    }
    
    func startSession() {
        guard !isRunning else { return }
        isRunning = true
        
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
                    self.isRunning = false
                }
            }
        }
    }
    
    func stopSession() {
        guard isRunning else { return }
        
        micService.stop()
        sysAudioService.stop()
        whisperEngine.cancel()
        llmEngine.cancel()
        
        isRunning = false
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
            responseGenerator.handleQuestionDetected(text)
        }
    }
}
