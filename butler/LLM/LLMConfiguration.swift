import Foundation

struct LLMConfiguration {

    var activeProfile: ModelProfile {
        if let savedString = UserDefaults.standard.string(forKey: ConfigKey.modelProfile),
           let profile = ModelProfile(rawValue: savedString) {
            return profile
        }
        return .fast
    }
    
    var contextSize: Int { activeProfile.configuration.contextSize }
    
    var temperature: Float {
        let val = UserDefaults.standard.double(forKey: ConfigKey.llmTemperature)
        return val > 0 ? Float(val) : activeProfile.configuration.temperature
    }
    
    var maxTokens: Int {
        let val = UserDefaults.standard.integer(forKey: ConfigKey.llmMaxTokens)
        return val > 0 ? val : activeProfile.configuration.maxTokens
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
}
