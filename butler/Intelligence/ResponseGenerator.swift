import Foundation

class ResponseGenerator {
    private let contextManager: ContextManager
    private let promptBuilder: PromptBuilder
    private let llmEngine: LLMEngine
    private var currentGenerationTask: Task<Void, Never>?
    
    var onTokenGenerated: ((String) -> Void)?
    var onResponseCompleted: (() -> Void)?
    
    init(contextManager: ContextManager, promptBuilder: PromptBuilder, llmEngine: LLMEngine) {
        self.contextManager = contextManager
        self.promptBuilder = promptBuilder
        self.llmEngine = llmEngine
    }
    
    func handleQuestionDetected(_ question: String) {
        currentGenerationTask?.cancel()
        llmEngine.cancel()
        
        currentGenerationTask = Task {
            let context = contextManager.getRecentContext()
            let prompt = promptBuilder.build(context: context, question: question)
            
            do {
                try await llmEngine.generateStreaming(prompt: prompt) { [weak self] token in
                    self?.onTokenGenerated?(token)
                }
                onResponseCompleted?()
            } catch {
                print("LLM generation failed: \(error)")
            }
        }
    }
}
