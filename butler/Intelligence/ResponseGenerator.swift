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
        
        currentGenerationTask = Task { [weak self] in
            guard let self = self else { return }
            let context = await self.contextManager.getRecentContext()
            let prompt = promptBuilder.build(context: context, question: transcript)
            
            var buffer = ""
            var decisionMade = false
            var isIntentValid = false
            var strippedLeadingNoise = false
            
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
                            
                            var remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                            if remaining.uppercased().hasPrefix("YES|") {
                                remaining = String(remaining.dropFirst(4))
                            } else if remaining.uppercased().hasPrefix("YES") {
                                remaining = String(remaining.dropFirst(3))
                            }
                            
                            remaining = remaining.trimmingCharacters(in: CharacterSet(charactersIn: " |:\n\t"))
                            
                            if !remaining.isEmpty {
                                strippedLeadingNoise = true
                                self.onTokenGenerated?(remaining)
                            }
                        } else if trimmedUpper.hasPrefix("NO") {
                            decisionMade = true
                            isIntentValid = false
                            self.llmEngine.cancel()
                        } else if buffer.count > 20 {
                            // Model failed to output YES/NO, but is generating text. Assume it's answering directly.
                            decisionMade = true
                            isIntentValid = true
                            strippedLeadingNoise = true
                            self.onIntentConfirmed?(transcript)
                            self.onTokenGenerated?(buffer)
                        }
                    } else if isIntentValid {
                        if !strippedLeadingNoise {
                            let noiseChars = CharacterSet(charactersIn: " |:\n\t")
                            let trimmedToken = token.trimmingCharacters(in: noiseChars)
                            if !trimmedToken.isEmpty {
                                strippedLeadingNoise = true
                                if let idx = token.firstIndex(where: { !noiseChars.contains($0.unicodeScalars.first!) }) {
                                    self.onTokenGenerated?(String(token[idx...]))
                                } else {
                                    self.onTokenGenerated?(trimmedToken)
                                }
                            }
                        } else {
                            self.onTokenGenerated?(token)
                        }
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
