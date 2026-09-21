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
    @Published var transcripts: [TranscriptSegment] = []
    @Published var isLoadingModels: Bool = false
    
    private let vadQueue = DispatchQueue(label: "com.butler.vadQueue", qos: .userInitiated)
    
    private var speechStartTimestamp: TimeInterval?
    private var sysSpeechStartTimestamp: TimeInterval?
    private var prevMicSpeaking = false
    private var prevSysSpeaking = false
    
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
            DispatchQueue.main.async {
                self?.overlayViewModel.statusText = "Completed"
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                // Clear the UI if a new question hasn't started
                if self?.overlayViewModel.statusText == "Completed" {
                    self?.overlayViewModel.clearLLMResponse()
                }
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
        
        let turn = ConversationTurn(id: UUID(), source: segment.source, text: segment.text, timestamp: Date())
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
    
    private func handleMicSamples(_ samples: [Float]) {
        micRingBuffer.push(samples, timestamp: mach_absolute_time())
        vadQueue.async { [weak self] in
            guard let self = self else { return }
            let rms = self.calculateRMS(samples)
            let ts = Date().timeIntervalSince1970
            let isSpeaking = self.micVAD.process(rms: rms, timestamp: ts)
            let justEnded = !isSpeaking && self.prevMicSpeaking
            let justStarted = isSpeaking && !self.prevMicSpeaking
            self.prevMicSpeaking = isSpeaking
            
            if justStarted { self.speechStartTimestamp = ts }
            if justEnded, let start = self.speechStartTimestamp {
                self.speechStartTimestamp = nil
                let duration = ts - start
                guard duration > 0.5 else { return }
                let count = Int(duration * 16000)
                let captured = self.micRingBuffer.getRecent(samplesCount: count)
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self, await self.sessionIsActive() else { return }
                    await MainActor.run { self.state = .processing }
                    try? await self.whisperEngine.transcribe(samples: captured, sampleRate: 16000, source: .microphone)
                }
            }
        }
    }
    
    private func handleSysSamples(_ samples: [Float]) {
        sysRingBuffer.push(samples, timestamp: mach_absolute_time())
        vadQueue.async { [weak self] in
            guard let self = self else { return }
            let rms = self.calculateRMS(samples)
            let ts = Date().timeIntervalSince1970
            let isSpeaking = self.sysVAD.process(rms: rms, timestamp: ts)
            let justEnded = !isSpeaking && self.prevSysSpeaking
            let justStarted = isSpeaking && !self.prevSysSpeaking
            self.prevSysSpeaking = isSpeaking
            
            if justStarted { self.sysSpeechStartTimestamp = ts }
            if justEnded, let start = self.sysSpeechStartTimestamp {
                self.sysSpeechStartTimestamp = nil
                let duration = ts - start
                guard duration > 0.5 else { return }
                let count = Int(duration * 16000)
                let captured = self.sysRingBuffer.getRecent(samplesCount: count)
                Task.detached(priority: .userInitiated) { [weak self] in
                    guard let self else { return }
                    try? await self.whisperEngine.transcribe(samples: captured, sampleRate: 16000, source: .system)
                }
            }
        }
    }
    
    @MainActor private func sessionIsActive() -> Bool { state == .listening }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }
    
    func startSession() {
        guard state == .idle else { return }
        state = .listening
        isLoadingModels = true
        
        Task {
            do {
                try await whisperEngine.load()
                try await llmEngine.load()
                
                try await micService.start()
                try await sysAudioService.start()
                
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
        
        micService.stop()
        sysAudioService.stop()
        whisperEngine.cancel()
        llmEngine.cancel()
        MemoryMonitor.shared.stopMonitoring()
        
        state = .idle
        print("Session stopped.")
    }
    
    // For testing
    func simulateSpeechDetected(text: String, source: AudioSource) {
        let segment = TranscriptSegment(id: UUID(), source: source, startTime: 0, endTime: 0, text: text, isFinal: true, confidence: 1.0)
        transcriptAssembler.addSegment(segment)
        
        let turn = ConversationTurn(id: UUID(), source: source, text: text, timestamp: Date())
        Task { await contextManager.addTurn(turn) }
        
        DispatchQueue.main.async {
            self.overlayViewModel.appendSubtitle(text)
        }
        
        questionDetector.process(transcript: text, source: source)
    }
}
