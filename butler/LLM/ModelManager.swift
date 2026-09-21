import Foundation

class ModelManager {
    func validateModels() throws {
        let fileManager = FileManager.default
        
        let whisperPath = WhisperConfiguration().getModelPath()
        let llmPath = LLMConfiguration().getModelPath()
        
        if !fileManager.fileExists(atPath: whisperPath) {
            throw AssistantError.modelNotFound("Whisper model not found. Please place 'ggml-base.en.bin' in \(whisperPath).")
        }
        
        if !fileManager.fileExists(atPath: llmPath) {
            throw AssistantError.modelNotFound("LLM model not found. Please place 'Llama-3.2-3B-Instruct.gguf' in \(llmPath).")
        }
    }
    
    func downloadModels() async throws {
        // Downloading via bash script inside bundle is unsupported in a real macOS app.
        // Users must place models manually in Application Support for now.
        let defaultPath = Constants.modelsDirectory?.path ?? "~/Library/Application Support/RealtimeAssistant/Models/"
        throw AssistantError.modelNotFound("Automatic model download is not supported. Please place models manually in \(defaultPath)")
    }
}
