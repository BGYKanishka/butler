import Foundation

struct WhisperConfiguration {

    func getModelPath() -> String {
        let customPath = UserDefaults.standard.string(forKey: "whisperModelPath") ?? ""
        if !customPath.isEmpty {
            return customPath
        }
        
        return Constants.whisperModelPath ?? ""
    }
}
