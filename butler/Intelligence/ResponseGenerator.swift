import Foundation

class ResponseGenerator {
    private let contextManager: ContextManager
    private let promptBuilder: PromptBuilder
    private let llmEngine: LLMEngine
    private var currentGenerationTask: Task<Void, Never>?
    
    var onIntentConfirmed: ((String) -> Void)?
    var onTokenGenerated: ((String) -> Void)?
    var onResponseCompleted: (() -> Void)?
    var onResponseIgnored: (() -> Void)?
    
    init(contextManager: ContextManager, promptBuilder: PromptBuilder, llmEngine: LLMEngine) {
        self.contextManager = contextManager
        self.promptBuilder = promptBuilder
        self.llmEngine = llmEngine
    }
    
    func handleTranscript(_ transcript: String) {
        currentGenerationTask?.cancel()
        llmEngine.cancel()
        
        currentGenerationTask = Task {
            let context = await contextManager.getRecentContext()
            let prompt = promptBuilder.build(context: context, question: transcript)
            
            var buffer = ""
            var decisionMade = false
            var isIntentValid = false
            
            do {
                try await llmEngine.generateStreaming(prompt: prompt) { [weak self] token in
                    guard let self = self else { return }
                    
                    if !decisionMade {
                        buffer += token
                        let trimmedUpper = buffer.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if trimmedUpper.hasPrefix("YES") {
                            decisionMade = true
                            isIntentValid = true
                            self.onIntentConfirmed?(transcript)
                            
                            // Try to strip "YES|" or "YES"
                            var remaining = buffer
                            if remaining.uppercased().hasPrefix("YES|") {
                                remaining = String(remaining.dropFirst(4))
                            } else if remaining.uppercased().hasPrefix("YES") {
                                remaining = String(remaining.dropFirst(3))
                            }
                            
                            // Strip any leading punctuation or space
                            remaining = remaining.trimmingCharacters(in: CharacterSet(charactersIn: " |:\n\t"))
                            
                            if !remaining.isEmpty {
                                self.onTokenGenerated?(remaining)
                            }
                        } else if trimmedUpper.hasPrefix("NO") || buffer.count > 15 {
                            decisionMade = true
                            isIntentValid = false
                            self.llmEngine.cancel()
                        }
                    } else if isIntentValid {
                        self.onTokenGenerated?(token)
                    }
                }
                
                if isIntentValid {
                    self.onResponseCompleted?()
                } else {
                    self.onResponseIgnored?()
                }
            } catch {
                print("LLM generation failed: \(error)")
            }
        }
    }
}
