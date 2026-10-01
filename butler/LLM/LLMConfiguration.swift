import Foundation

struct LLMConfiguration {

    var activeProfile: ModelProfile {
        if let savedString = UserDefaults.standard.string(forKey: ConfigKey.modelProfile),
           let profile = ModelProfile(rawValue: savedString) {
            return profile
        }
        // `.balanced` (16k window): `.fast` (8k) left almost no room for conversation history once the
        // project summary, retrieved code and the answer budget were reserved.
        return .balanced
    }
    
    var contextSize: Int { activeProfile.configuration.contextSize }
    
    var temperature: Float {
        let val = UserDefaults.standard.double(forKey: ConfigKey.llmTemperature)
        return val > 0 ? Float(val) : activeProfile.configuration.temperature
    }
    
    /// Values below 256 are treated as stale/invalid (no Settings control writes this key, so a tiny
    /// value is a leftover from an old build or a manual `defaults write`) and would cut every answer
    /// off mid-sentence.
    var maxTokens: Int {
        let val = UserDefaults.standard.integer(forKey: ConfigKey.llmMaxTokens)
        return val >= 256 ? val : activeProfile.configuration.maxTokens
    }
    
    var modelFileName: String { activeProfile.configuration.fileName }
    
    func getModelPath() -> String {
        // 1. User-specified custom path takes priority
        let customPath = UserDefaults.standard.string(forKey: ConfigKey.llamaModelPath) ?? ""
        if !customPath.isEmpty {
            return customPath
        }
        
        guard let llmDir = Constants.llmModelsDirectory else { return "" }
        
        // 2. Try the profile-specific model
        let profilePath = (llmDir as NSString).appendingPathComponent(modelFileName)
        if FileManager.default.fileExists(atPath: profilePath) {
            return profilePath
        }
        
        // 3. Fall back to any .gguf file in the llm directory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: llmDir) {
            if let firstGGUF = contents.first(where: { $0.hasSuffix(".gguf") && !$0.contains("mmproj") }) {
                return (llmDir as NSString).appendingPathComponent(firstGGUF)
            }
        }
        
        // 4. Nothing found — return the profile path so the error message is informative
        return profilePath
    }
    func getVisionModelPath() -> String? {
        guard let llmDir = Constants.llmModelsDirectory else { return nil }
        
        // Try to find an mmproj file in the llm models directory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: llmDir) {
            if let firstMMProj = contents.first(where: { $0.hasSuffix(".gguf") && $0.contains("mmproj") }) {
                return (llmDir as NSString).appendingPathComponent(firstMMProj)
            }
        }
        return nil
    }
}
