import Foundation
import Combine
import AVFoundation

final class SessionCoordinator: ObservableObject, @unchecked Sendable {
    let environment: AppEnvironment
    
    var micService: MicrophoneCaptureService { environment.micService }
    var sysAudioService: SystemAudioCaptureService { environment.sysAudioService }
    var audioSessionCoordinator: AudioSessionCoordinator { environment.audioSessionCoordinator }
    var whisperEngine: WhisperEngine { environment.whisperEngine }
    var llmEngine: LLMEngine { environment.llmEngine }
    var contextManager: ContextManager { environment.contextManager }
    var promptBuilder: PromptBuilder { environment.promptBuilder }

    var transcriptAssembler: TranscriptAssembler { environment.transcriptAssembler }
    
    lazy var responseGenerator = ResponseGenerator(contextManager: contextManager, promptBuilder: promptBuilder, llmEngine: llmEngine)
    
    @Published var overlayViewModel = OverlayViewModel()
    @Published var state: SessionState = .idle
    @Published var transcripts: [TranscriptSegment] = []
    @Published var isLoadingModels: Bool = false
    @Published var micAudioLevel: Float = 0.0
    @Published var sysAudioLevel: Float = 0.0
    
    init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        setupBindings()
    }
    
    private func setupBindings() {
        responseGenerator.onTokenGenerated = { [weak self] token in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.overlayViewModel.appendLLMToken(token)
                
                // Stream directly into transcript
                if let last = self.transcripts.last, last.source == .assistant, !last.isFinal {
                    var updated = last
                    updated.text += token
                    self.transcripts[self.transcripts.count - 1] = updated
                } else {
                    let newSeg = TranscriptSegment(id: UUID(), source: .assistant, startTime: Date().timeIntervalSince1970, endTime: Date().timeIntervalSince1970, text: token, isFinal: false, confidence: 1.0)
                    self.transcripts.append(newSeg)
                }
            }
        }
        
        responseGenerator.onResponseCompleted = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, self.state == .answering else { return }
                self.overlayViewModel.statusText = "Completed"
                self.state = .listening // M7: Reset state so session can continue
                
                // Mark the last assistant segment as final
                if let last = self.transcripts.last, last.source == .assistant, !last.isFinal {
                    var updated = last
                    updated.isFinal = true
                    self.transcripts[self.transcripts.count - 1] = updated
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                // Clear the UI if a new question hasn't started
                if self?.overlayViewModel.statusText == "Completed" {
                    self?.overlayViewModel.clearLLMResponse()
                }
            }
        }
        
        audioSessionCoordinator.micService.onAudioLevelChanged = { [weak self] level in
            DispatchQueue.main.async { self?.micAudioLevel = level }
        }
        
        audioSessionCoordinator.sysAudioService.onAudioLevelChanged = { [weak self] level in
            DispatchQueue.main.async { self?.sysAudioLevel = level }
        }
        
        audioSessionCoordinator.onSpeechDetected = { [weak self] samples, source in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self, await self.sessionIsActive() else { return }
                print("Session Info: Speech detected from \(source), transcribing...")
                do {
                    try await self.whisperEngine.transcribe(samples: samples, sampleRate: 16000, source: source)
                } catch {
                    print("Session Error: Transcription failed: \(error)")
                    await MainActor.run {
                        self.state = .error(error)
                    }
                }
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
        
        responseGenerator.onIntentConfirmed = { [weak self] question in
            print("Session Info: Intent confirmed by LLM! -> \(question)")
            DispatchQueue.main.async {
                self?.overlayViewModel.setQuestion(question)
                self?.state = .answering
            }
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
            // Pass every transcript directly to the ResponseGenerator to evaluate intent
            // ONLY if not already answering, to prevent cancelling the ongoing answer
            if self.state != .answering {
                self.responseGenerator.handleTranscript(segment.text, source: segment.source)
            }
        }
    }
    
    @MainActor private func sessionIsActive() -> Bool {
        switch state {
        case .idle, .error: return false
        default: return true
        }
    }
    
    func startSession() {
        guard state == .idle else { return }
        
        Task { @MainActor in
            let gateway = self.environment.permissionsGateway
            
            // Allow starting a session as long as ANY hardware permission is granted.
            // If they only have System Audio or Vision, we can still run those pipelines.
            if gateway.anyPermissionGranted {
                self.startSessionInternal(micGranted: gateway.isMicGranted)
            } else {
                let granted = await gateway.requestMicPermission()
                if granted {
                    self.startSessionInternal(micGranted: true)
                } else {
                    self.state = .error(AssistantError.permissionDenied("At least one permission (Mic or System Audio) is required to start a session"))
                }
            }
        }
    }
    
    private func startSessionInternal(micGranted: Bool) {
        state = .listening
        isLoadingModels = true
        
        Task {
            do {
                let modelManager = ModelManager()
                try modelManager.validateModels()
                
                try await whisperEngine.load()
                try await llmEngine.load()
                
                let _ = UserDefaults.standard.bool(forKey: ConfigKey.isVisionEnabled)
                try await audioSessionCoordinator.start(includeSystemAudio: self.environment.permissionsGateway.isScreenGranted, micGranted: micGranted)
                
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
    

}
