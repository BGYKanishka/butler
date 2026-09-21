import Foundation

class AppEnvironment: ObservableObject {
    let micService: MicrophoneCaptureService
    let sysAudioService: SystemAudioCaptureService
    let audioSessionCoordinator: AudioSessionCoordinator
    let whisperEngine: WhisperEngine
    let llmEngine: LLMEngine
    let contextManager: ContextManager
    let promptBuilder: PromptBuilder
    let questionDetector: QuestionDetector
    let transcriptAssembler: TranscriptAssembler
    let permissionsGateway: PermissionsGateway
    
    init(llmEngine: LLMEngine = LocalLLMEngine()) {
        self.micService = MicrophoneCaptureService()
        self.sysAudioService = SystemAudioCaptureService()
        self.audioSessionCoordinator = AudioSessionCoordinator(micService: micService, sysAudioService: sysAudioService)
        self.whisperEngine = WhisperEngine()
        self.llmEngine = llmEngine
        self.contextManager = ContextManager()
        self.promptBuilder = PromptBuilder()
        self.questionDetector = QuestionDetector()
        self.transcriptAssembler = TranscriptAssembler()
        self.permissionsGateway = MainActor.assumeIsolated { PermissionsGateway() }
    }
}
