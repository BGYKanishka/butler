import Foundation

class LocalLLMEngine: LLMEngine, @unchecked Sendable {
    private let wrapper = LlamaWrapper()
    private let config = LLMConfiguration()
    private var isLoaded = false
    private let inferenceQueue = DispatchQueue(label: "com.butler.llmQueue")
    
    func load() async throws {
        guard !isLoaded else { return }
        
        let modelPath = config.getModelPath()
        guard !modelPath.isEmpty, FileManager.default.fileExists(atPath: modelPath) else {
            print("LLM Error: Model not found at path: \(modelPath)")
            throw AssistantError.modelNotFound("LLM model not found at path: \(modelPath)")
        }
        
        do {
            print("LLM Info: Loading model from \(modelPath)...")
            let startTime = Date()
            if let visionPath = config.getVisionModelPath(), FileManager.default.fileExists(atPath: visionPath) {
                print("LLM Info: Loading vision model projector from \(visionPath)...")
                do {
                    try wrapper.loadVisionModel(modelPath, mmprojPath: visionPath, contextSize: Int32(config.contextSize))
                } catch {
                    print("LLM Warning: Failed to load vision model projector. Falling back to text-only mode. Error: \(error.localizedDescription)")
                    try wrapper.loadModel(modelPath, contextSize: Int32(config.contextSize))
                }
            } else {
                try wrapper.loadModel(modelPath, contextSize: Int32(config.contextSize))
            }
            print("LLM Info: Model loaded successfully in \(String(format: "%.2f", Date().timeIntervalSince(startTime)))s")
        } catch {
            print("LLM Error: Failed to load model: \(error.localizedDescription)")
            throw AssistantError.modelNotFound(error.localizedDescription)
        }
        
        isLoaded = true
        
        // Attempt to load binary project memory if it exists
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let binaryPath = docs.appendingPathComponent("butler_project_memory.bin").path
        if FileManager.default.fileExists(atPath: binaryPath) {
            print("LLM Info: Found existing binary project memory. Loading...")
            do {
                try wrapper.loadState(fromPath: binaryPath)
                print("LLM Info: Successfully loaded binary project memory")
            } catch {
                print("LLM Warning: Failed to load binary project memory: \(error)")
            }
        }
    }
    
    func unload() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inferenceQueue.async {
                self.wrapper.unload()
                self.isLoaded = false
                continuation.resume()
            }
        }
    }
    
    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws {
        guard isLoaded else { 
            print("LLM Error: Attempted to generate but model is not loaded")
            throw AssistantError.inferenceFailed("Model not loaded") 
        }
        
        print("LLM Info: Starting generation with prompt:\n\(prompt)")
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inferenceQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                var tokenCount = 0
                let startTime = Date()
                
                self.wrapper.generateStreaming(prompt, temperature: self.config.temperature, maxTokens: Int32(self.config.maxTokens)) { token in
                    tokenCount += 1
                    onToken(token)
                }
                
                let duration = Date().timeIntervalSince(startTime)
                print("LLM Info: Generation completed. Generated \(tokenCount) tokens in \(String(format: "%.2f", duration))s (\(String(format: "%.2f", duration > 0 ? Double(tokenCount) / duration : 0)) tokens/sec)")
                continuation.resume()
            }
        }
    }
    
    func generateVisionStreaming(prompt: String, imagePath: String, onToken: @escaping (String) -> Void) async throws {
        guard isLoaded else { 
            print("LLM Error: Attempted to generate vision but model is not loaded")
            throw AssistantError.inferenceFailed("Model not loaded") 
        }
        
        print("LLM Info: Starting vision generation for image \(imagePath) with prompt:\n\(prompt)")
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inferenceQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                var tokenCount = 0
                let startTime = Date()
                
                self.wrapper.generateVisionStreaming(prompt, imagePath: imagePath, temperature: self.config.temperature, maxTokens: Int32(self.config.maxTokens)) { token in
                    tokenCount += 1
                    onToken(token)
                }
                
                let duration = Date().timeIntervalSince(startTime)
                print("LLM Info: Vision generation completed. Generated \(tokenCount) tokens in \(String(format: "%.2f", duration))s (\(String(format: "%.2f", duration > 0 ? Double(tokenCount) / duration : 0)) tokens/sec)")
                continuation.resume()
            }
        }
    }
    
    func saveState(to path: String, prompt: String) async throws {
        guard isLoaded else { throw AssistantError.inferenceFailed("Model not loaded") }
        print("LLM Info: Generating binary memory state for project...")
        
        return try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated"))
                    return
                }
                
                do {
                    try self.wrapper.saveState(toPath: path, prompt: prompt)
                    print("LLM Info: Successfully saved binary memory state to \(path)")
                    continuation.resume()
                } catch {
                    print("LLM Error: Failed to save binary memory state: \(error.localizedDescription)")
                    continuation.resume(throwing: AssistantError.inferenceFailed(error.localizedDescription))
                }
            }
        }
    }
    
    func loadState(from path: String) async throws {
        guard isLoaded else { throw AssistantError.inferenceFailed("Model not loaded") }
        print("LLM Info: Loading binary memory state from \(path)...")
        
        return try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: AssistantError.inferenceFailed("Engine deallocated"))
                    return
                }
                
                do {
                    try self.wrapper.loadState(fromPath: path)
                    print("LLM Info: Successfully loaded binary memory state")
                    continuation.resume()
                } catch {
                    print("LLM Error: Failed to load binary memory state: \(error.localizedDescription)")
                    continuation.resume(throwing: AssistantError.inferenceFailed(error.localizedDescription))
                }
            }
        }
    }
    
    func cancel() {
        wrapper.cancel()
    }
}
