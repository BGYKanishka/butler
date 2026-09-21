import Foundation

struct Constants {
    static let appSupportDirectoryName = "RealtimeAssistant"
    
    static var modelsDirectory: URL? {
        guard let appSupportURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return appSupportURL.appendingPathComponent("\(appSupportDirectoryName)/Models")
    }
    
    static var whisperModelPath: String? {
        return modelsDirectory?.appendingPathComponent("whisper/ggml-base.en.bin").path
    }
    
    static var llmModelPath: String? {
        return modelsDirectory?.appendingPathComponent("llm/\(LLMConfiguration().modelFileName)").path
    }
}
