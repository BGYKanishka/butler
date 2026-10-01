import Foundation

struct Constants {
    static let appSupportDirectoryName = "butler"
    
    static var modelsDirectory: URL? {
        guard let appSupportURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            return nil
        }
        return appSupportURL.appendingPathComponent("\(appSupportDirectoryName)/Models")
    }
    
    static var whisperModelPath: String? {
        return modelsDirectory?.appendingPathComponent("whisper/ggml-small.en.bin").path
    }
    
    static var llmModelsDirectory: String? {
        return modelsDirectory?.appendingPathComponent("llm").path
    }

    static var projectMemoryStatePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("butler_project_memory.bin").path
    }
}
