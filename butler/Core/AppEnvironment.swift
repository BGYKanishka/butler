import Foundation

class AppEnvironment: ObservableObject {
    let micService: MicrophoneCaptureService
    let sysAudioService: SystemAudioCaptureService
    let audioSessionCoordinator: AudioSessionCoordinator
    let whisperEngine: WhisperEngine
    let llmEngine: LLMEngine
    let contextManager: ContextManager
    let promptBuilder: PromptBuilder

    let transcriptAssembler: TranscriptAssembler
    let permissionsGateway: PermissionsGateway
    let projectContextManager: ProjectContextManager
    let indexCoordinator: ProjectIndexCoordinator?
    let projectRetriever: ProjectRetrievalService?
    
    @MainActor
    init(llmEngine: LLMEngine = LocalLLMEngine()) {
        self.micService = MicrophoneCaptureService()
        self.sysAudioService = SystemAudioCaptureService()
        self.audioSessionCoordinator = AudioSessionCoordinator(micService: micService, sysAudioService: sysAudioService)
        self.whisperEngine = WhisperEngine()
        self.llmEngine = llmEngine
        self.contextManager = ContextManager()
        self.promptBuilder = PromptBuilder()

        self.transcriptAssembler = TranscriptAssembler()
        self.permissionsGateway = PermissionsGateway()
        
        var dbPath = ":memory:"
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
           let appSupport = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let dir = appSupport.appendingPathComponent("\(Constants.appSupportDirectoryName)/Index")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbPath = dir.appendingPathComponent("index.sqlite").path
        }
        
        let coordinator = try? ProjectIndexCoordinator(dbPath: dbPath)
        self.indexCoordinator = coordinator
        self.projectContextManager = ProjectContextManager(llmEngine: llmEngine, indexCoordinator: coordinator)
        if coordinator != nil, let db = try? SQLiteDatabase(path: dbPath) {
            let retriever = HybridProjectRetriever(db: db)
            self.projectRetriever = retriever
            // Wire back-reference so the coordinator can flush the lexicon cache after each sync.
            Task { await coordinator?.setRetriever(retriever) }
        } else {
            self.projectRetriever = nil
        }
        
        self.projectContextManager.restoreSavedProjects()
    }
}
