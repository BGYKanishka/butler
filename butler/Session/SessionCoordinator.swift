import Foundation
import Combine
import AVFoundation
import AppKit

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
    
    var onHideMainWindow: (() -> Void)?
    var onShowMainWindow: (() -> Void)?
    var onShowSettings: (() -> Void)?
    
    @Published var state: SessionState = .idle
    @Published var transcripts: [TranscriptSegment] = []
    @Published var isLoadingModels: Bool = false
    @Published var micAudioLevel: Float = 0.0
    @Published var sysAudioLevel: Float = 0.0
    
    private var lastPartialEvalTime: Date = .distantPast
    private var lastAnswerEndTime: Date = .distantPast
    
    init(environment: AppEnvironment = AppEnvironment()) {
        self.environment = environment
        setupBindings()
    }
    
    private func setupBindings() {
        responseGenerator.onTokenGenerated = { [weak self] token in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
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
                self.lastAnswerEndTime = Date()
                self.state = .listening // M7: Reset state so session can continue
                
                // Mark the last assistant segment as final
                if let last = self.transcripts.last, last.source == .assistant, !last.isFinal {
                    var updated = last
                    updated.isFinal = true
                    self.transcripts[self.transcripts.count - 1] = updated
                }
            }
            
            // Delay logic removed
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
                guard let self = self else { return }
                
                // Allow model to evaluate intent early on incomplete sentences!
                if self.state != .answering && Date().timeIntervalSince(self.lastAnswerEndTime) > 3.0 {
                    let now = Date()
                    // Throttle to give the LLM time to generate "YES" before cancelling it again
                    if now.timeIntervalSince(self.lastPartialEvalTime) > 1.5 {
                        self.lastPartialEvalTime = now
                        self.responseGenerator.handleTranscript(segment.text, source: segment.source)
                    }
                }
            }
        }
        
        responseGenerator.onIntentConfirmed = { [weak self] question in
            print("Session Info: Intent confirmed by LLM! -> \(question)")
            DispatchQueue.main.async {
                self?.state = .answering
            }
        }
    }
    
    private func handleTranscription(segment: TranscriptSegment) {
        transcriptAssembler.addSegment(segment)
        
        let turn = ConversationTurn(id: UUID(), source: segment.source, type: .statement, text: segment.text, timestamp: Date())
        Task { await contextManager.addTurn(turn) }
        
        DispatchQueue.main.async {
            self.transcripts.append(segment)
            if self.transcripts.count > 100 {
                self.transcripts.removeFirst(self.transcripts.count - 100)
            }
            
            // Clear context to prevent Whisper hallucination loops. It relies on the user-configured Vocabulary.
            self.whisperEngine.updateContext("")
            
            // Evaluate intent if not currently answering to prevent cancelling the ongoing response.
            if self.state != .answering && Date().timeIntervalSince(self.lastAnswerEndTime) > 3.0 {
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
            
            // Sessions can start without permissions for Vision-only mode. Audio capture fails gracefully.
            self.startSessionInternal(micGranted: gateway.isMicGranted)
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
        whisperEngine.unload()
        llmEngine.cancel()
        llmEngine.unload()
        MemoryMonitor.shared.stopMonitoring()
        
        DispatchQueue.main.async {
            self.transcripts.removeAll()
        }
        
        state = .idle
        print("Session stopped.")
    }
    
    func triggerVisionAnalysis() {
        // Prevent vision request if we are already answering, error, idle, or loading
        if isLoadingModels || state == .idle {
            print("Cannot analyze screen in current state.")
            return
        }
        if case .error = state {
            print("Cannot analyze screen in current state.")
            return
        }
        
        // Hide the UI window before taking the screenshot
        DispatchQueue.main.async {
            self.onHideMainWindow?()
        }
        
        InteractiveCaptureService.shared.captureRegion { [weak self] fileUrl in
            guard let self = self else { return }
            
            // Show the UI window again
            DispatchQueue.main.async {
                self.onShowMainWindow?()
                
                guard let imagePath = fileUrl?.path else { return }
                
                Task {
                    let recentContext = await self.contextManager.getRecentContext()
                    let basePrompt = "Analyze this image. If it contains a multiple-choice question or a direct problem, you MUST state the final answer clearly in the very first sentence. After that, provide your step-by-step solution and explanation."
                    
                    let finalPrompt = recentContext.isEmpty ? basePrompt : "\(basePrompt)\n\nRecent voice/chat context:\n\(recentContext)\n\nPlease answer the user's latest query considering the image."
                    
                    await MainActor.run {
                        self.processVisionRequest(prompt: finalPrompt, imagePath: imagePath)
                    }
                }
            }
        }
    }
    
    private func processVisionRequest(prompt: String, imagePath: String) {
        // Clear old overlays
        state = .answering
        
        // Display image instead of long text prompt in chat transcript
        let userSeg = TranscriptSegment(id: UUID(), source: .microphone, startTime: Date().timeIntervalSince1970, endTime: Date().timeIntervalSince1970, text: "Image Analyzed", isFinal: true, confidence: 1.0, imagePath: imagePath)
        transcripts.append(userSeg)
        
        let aiSegId = UUID()
        let initialAiSeg = TranscriptSegment(id: aiSegId, source: .assistant, startTime: Date().timeIntervalSince1970, endTime: Date().timeIntervalSince1970, text: "", isFinal: false, confidence: 1.0)
        transcripts.append(initialAiSeg)
        
        Task {
            do {
                try await llmEngine.generateVisionStreaming(prompt: prompt, imagePath: imagePath) { token in
                    DispatchQueue.main.async {
                        // Stream into the chat view
                        if let lastIdx = self.transcripts.indices.last {
                            var updated = self.transcripts[lastIdx]
                            updated.text += token
                            self.transcripts[lastIdx] = updated
                        }
                    }
                }
                DispatchQueue.main.async {
                    if let lastIdx = self.transcripts.indices.last {
                        self.transcripts[lastIdx].isFinal = true
                    }
                    self.state = .listening
                }
            } catch {
                print("Vision error: \(error)")
                DispatchQueue.main.async {
                    self.state = .error(error)
                }
            }
        }
    }
    

}
