import Foundation

class LocalLLMEngine: LLMEngine {
    private let wrapper = LlamaWrapper()
    private let config = LLMConfiguration()
    private var isLoaded = false
    
    func load() async throws {
        guard !isLoaded else { return }
        
        let modelPath = config.getModelPath()
        guard !modelPath.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
            throw AssistantError.modelNotFound("LLM model not found at path: \(modelPath)")
        }
        
        do {
            try wrapper.loadModel(modelPath, contextSize: Int32(config.contextSize))
        } catch {
            throw AssistantError.modelNotFound(error.localizedDescription)
        }
        
        isLoaded = true
    }
    
    func unload() {
        wrapper.unload()
        isLoaded = false
    }
    
    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws {
        guard isLoaded else { throw AssistantError.inferenceFailed("Model not loaded") }
        await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            self.wrapper.generateStreaming(prompt, temperature: self.config.temperature, maxTokens: Int32(self.config.maxTokens)) { token in
                onToken(token)
            }
        }.value
    }
    
    func cancel() {
        wrapper.cancel()
    }
}
