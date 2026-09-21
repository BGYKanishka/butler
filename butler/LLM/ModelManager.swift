import Foundation

class ModelManager {
    func validateModels() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        let whisperPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? appSupportURL.appendingPathComponent("butler/Models/whisper/ggml-base.en.bin").path
        
        let llmPath = LLMConfiguration().getModelPath()
        
        if !fileManager.fileExists(atPath: whisperPath) {
            throw AssistantError.modelNotFound("Whisper model not found at \(whisperPath).")
        }
        
        if !fileManager.fileExists(atPath: llmPath) {
            throw AssistantError.modelNotFound("LLM model not found at \(llmPath).")
        }
    }
    
    func downloadModels() async throws {
        let scriptPath = Bundle.main.path(forResource: "download_models", ofType: "sh") ?? ""
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw AssistantError.modelNotFound("Download script not found. Please place models manually.")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw AssistantError.initializationFailed("Model download failed with status \(process.terminationStatus)")
        }
    }
}
