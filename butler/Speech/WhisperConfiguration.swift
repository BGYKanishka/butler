import Foundation

struct WhisperConfiguration {
    var modelType: String = "base.en"
    var language: String = "en"
    
    func getModelPath() -> String {
        let customPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
        if !customPath.isEmpty {
            return customPath
        }
        
        return Constants.whisperModelPath ?? ""
    }
}
