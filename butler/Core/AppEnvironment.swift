import Foundation

class AppEnvironment: ObservableObject {
    let micService: MicrophoneCaptureService
    let sysAudioService: SystemAudioCaptureService
    let audioSessionCoordinator: AudioSessionCoordinator
    let whisperEngine: WhisperEngine
    let llmEngine: LocalLLMEngine
    let contextManager: ContextManager
    let promptBuilder: PromptBuilder
    let questionDetector: QuestionDetector
    let transcriptAssembler: TranscriptAssembler
    
    init() {
        self.micService = MicrophoneCaptureService()
        self.sysAudioService = SystemAudioCaptureService()
        self.audioSessionCoordinator = AudioSessionCoordinator(micService: micService, sysAudioService: sysAudioService)
        self.whisperEngine = WhisperEngine()
        self.llmEngine = LocalLLMEngine()
        self.contextManager = ContextManager()
        self.promptBuilder = PromptBuilder()
        self.questionDetector = QuestionDetector()
        self.transcriptAssembler = TranscriptAssembler()
    }
}
