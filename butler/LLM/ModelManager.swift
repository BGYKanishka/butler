import Foundation

class ModelManager {
    func validateModels() throws {
        let fileManager = FileManager.default
        
        let whisperPath = WhisperConfiguration().getModelPath()
        let llmConfig = LLMConfiguration()
        let llmPath = llmConfig.getModelPath()
        
        if !fileManager.fileExists(atPath: whisperPath) {
            throw AssistantError.modelNotFound("Whisper model not found. Please place 'ggml-small.en.bin' in \(whisperPath).")
        }
        
        if !fileManager.fileExists(atPath: llmPath) {
            throw AssistantError.modelNotFound("LLM model '\(llmConfig.modelFileName)' not found at \(llmPath). You can change the model profile in Settings.")
        }
    }
    
    func areModelsMissing() -> Bool {
        let fileManager = FileManager.default
        let whisperPath = WhisperConfiguration().getModelPath()
        let llmPath = LLMConfiguration().getModelPath()
        let visionPath = LLMConfiguration().getVisionModelPath()
        
        if !fileManager.fileExists(atPath: whisperPath) { return true }
        if !fileManager.fileExists(atPath: llmPath) { return true }
        if visionPath == nil || !fileManager.fileExists(atPath: visionPath!) { return true }
        
        return false
    }
}
