import Foundation

class LocalLLMEngine: LLMEngine {
    private let wrapper = LlamaWrapper()
    private let config = LLMConfiguration()
    private var isLoaded = false
    
    func load() async throws {
        guard !isLoaded else { return }
        
        let modelPath = config.getModelPath()
        
        do {
            try wrapper.loadModel(modelPath, contextSize: Int32(config.contextSize))
        } catch {
            throw AssistantError.modelNotFound("Model not found at \(modelPath)")
        }
        
        isLoaded = true
    }
    
    func unload() {
        wrapper.unload()
        isLoaded = false
    }
    
    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws {
        Task.detached { [weak self] in
            guard let self = self else { return }
            self.wrapper.generateStreaming(prompt, temperature: self.config.temperature, maxTokens: Int32(self.config.maxTokens)) { token in
                onToken(token)
            }
        }
    }
    
    func cancel() {
        wrapper.cancel()
    }
}
