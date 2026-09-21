import Foundation
import Combine
import AVFoundation

class SessionCoordinator: ObservableObject {
    let environment: AppEnvironment
    
    var micService: MicrophoneCaptureService { environment.micService }
    var sysAudioService: SystemAudioCaptureService { environment.sysAudioService }
    var audioSessionCoordinator: AudioSessionCoordinator { environment.audioSessionCoordinator }
    var whisperEngine: WhisperEngine { environment.whisperEngine }
    var llmEngine: LLMEngine { environment.llmEngine }
    var contextManager: ContextManager { environment.contextManager }
    var promptBuilder: PromptBuilder { environment.promptBuilder }
    var questionDetector: QuestionDetector { environment.questionDetector }
    var transcriptAssembler: TranscriptAssembler { environment.transcriptAssembler }
    
    lazy var responseGenerator = ResponseGenerator(contextManager: contextManager, promptBuilder: promptBuilder, llmEngine: llmEngine)
    
    @Published var overlayViewModel = OverlayViewModel()
    @Published var state: SessionState = .idle
    @Published var transcripts: [TranscriptSegment] = []
    @Published var isLoadingModels: Bool = false
    
    init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        setupBindings()
    }
    
    private func setupBindings() {
        responseGenerator.onTokenGenerated = { [weak self] token in
            DispatchQueue.main.async {
                self?.overlayViewModel.appendLLMToken(token)
            }
        }
        
        responseGenerator.onResponseCompleted = { [weak self] in
            DispatchQueue.main.async {
                self?.overlayViewModel.statusText = "Completed"
                self?.state = .listening // M7: Reset state so session can continue
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                // Clear the UI if a new question hasn't started
                if self?.overlayViewModel.statusText == "Completed" {
                    self?.overlayViewModel.clearLLMResponse()
                }
            }
        }
        
        audioSessionCoordinator.onSpeechDetected = { [weak self] samples, source in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self, await self.sessionIsActive() else { return }
                await MainActor.run { self.state = .processing }
                try? await self.whisperEngine.transcribe(samples: samples, sampleRate: 16000, source: source)
            }
        }
        
        whisperEngine.onTranscriptionCompleted = { [weak self] segment in
            self?.handleTranscription(segment: segment)
        }
        
        whisperEngine.onPartialTranscriptionCompleted = { [weak self] segment in
            DispatchQueue.main.async {
                // For partials, we might just update the UI
                self?.overlayViewModel.appendSubtitle(segment.text)
            }
        }
        
        questionDetector.onQuestionConfirmed = { [weak self] question in
            DispatchQueue.main.async {
                self?.overlayViewModel.setQuestion(question)
                self?.state = .answering
            }
            self?.responseGenerator.handleQuestionDetected(question)
        }
    }
    
    private func handleTranscription(segment: TranscriptSegment) {
        transcriptAssembler.addSegment(segment)
        
        let turn = ConversationTurn(id: UUID(), source: segment.source, type: .statement, text: segment.text, timestamp: Date())
        Task { await contextManager.addTurn(turn) }
        
        DispatchQueue.main.async {
            self.overlayViewModel.appendSubtitle(segment.text)
            self.transcripts.append(segment)
            if self.transcripts.count > 100 {
                self.transcripts.removeFirst(self.transcripts.count - 100)
            }
        }
        
        // Feed it to the question detector. If it triggers, it will call onQuestionConfirmed after a debounce.
        questionDetector.process(transcript: segment.text, source: segment.source)
    }
    
    @MainActor private func sessionIsActive() -> Bool { state == .listening }
    
    func startSession() {
        guard state == .idle else { return }
        
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.startSessionInternal()
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.state = .error(AssistantError.permissionDenied("Microphone access is required"))
                    }
                }
            }
        } else if status == .authorized {
            startSessionInternal()
        } else {
            state = .error(AssistantError.permissionDenied("Microphone access is required"))
        }
    }
    
    private func startSessionInternal() {
        state = .listening
        isLoadingModels = true
        
        Task {
            do {
                let modelManager = ModelManager()
                try modelManager.validateModels()
                
                try await whisperEngine.load()
                try await llmEngine.load()
                
                try await audioSessionCoordinator.start()
                
                MemoryMonitor.shared.startMonitoring()
                
                DispatchQueue.main.async {
                    self.isLoadingModels = false
                }
                print("Session started.")
            } catch {
                print("Failed to start session: \(error)")
                DispatchQueue.main.async {
                    self.isLoadingModels = false
                    self.state = .error(error)
                }
            }
        }
    }
    
    func stopSession() {
        guard state != .idle else { return }
        
        audioSessionCoordinator.stop()
        whisperEngine.cancel()
        llmEngine.cancel()
        MemoryMonitor.shared.stopMonitoring()
        
        DispatchQueue.main.async {
            self.transcripts.removeAll()
            self.overlayViewModel.clearLLMResponse()
            self.overlayViewModel.subtitles.removeAll()
        }
        
        state = .idle
        print("Session stopped.")
    }
    
    // For testing
    func simulateSpeechDetected(text: String, source: AudioSource) {
        let segment = TranscriptSegment(id: UUID(), source: source, startTime: 0, endTime: 0, text: text, isFinal: true, confidence: 1.0)
        transcriptAssembler.addSegment(segment)
        
        let turn = ConversationTurn(id: UUID(), source: source, type: .statement, text: text, timestamp: Date())
        Task { await contextManager.addTurn(turn) }
        
        DispatchQueue.main.async {
            self.overlayViewModel.appendSubtitle(text)
        }
        
        questionDetector.process(transcript: text, source: source)
    }
}
