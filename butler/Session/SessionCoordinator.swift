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
                print("Session Info: Speech detected from \(source), transcribing...")
                await MainActor.run { self.state = .processing }
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
        
        questionDetector.onQuestionConfirmed = { [weak self] question in
            print("Session Info: Question detected! -> \(question)")
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
        
        Task { @MainActor in
            let gateway = self.environment.permissionsGateway
            
            // Only mic permission is required to start a session.
            // Screen recording (system audio) is optional — AudioSessionCoordinator
            // will gracefully fall back to mic-only if it's not available.
            if gateway.isMicGranted {
                self.startSessionInternal()
            } else {
                let granted = await gateway.requestMicPermission()
                if granted {
                    self.startSessionInternal()
                } else {
                    self.state = .error(AssistantError.permissionDenied("Microphone access is required to start a session"))
                }
            }
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
    
    func testWithAudioFile(path: String) {
        print("Test Info: Starting audio file test with \(path)")
        
        // Ensure engines are loaded
        Task {
            do {
                if !self.isLoadingModels && self.state == .idle {
                    try await whisperEngine.load()
                    try await llmEngine.load()
                }
                
                let url = URL(fileURLWithPath: path)
                let file = try AVAudioFile(forReading: url)
                guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
                    print("Test Error: Could not create audio format")
                    return
                }
                
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
                    print("Test Error: Could not create buffer")
                    return
                }
                
                try file.read(into: buffer)
                
                guard let channelData = buffer.floatChannelData?[0] else {
                    print("Test Error: No channel data")
                    return
                }
                
                let frameLength = Int(buffer.frameLength)
                var samples = [Float](repeating: 0.0, count: frameLength)
                for i in 0..<frameLength {
                    samples[i] = channelData[i]
                }
                
                print("Test Info: Loaded \(samples.count) samples. Transcribing...")
                try await whisperEngine.transcribe(samples: samples, sampleRate: 16000, source: .microphone)
                print("Test Info: Transcription request sent.")
                
            } catch {
                print("Test Error: \(error)")
            }
        }
    }
}
