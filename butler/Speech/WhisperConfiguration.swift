import Foundation

struct WhisperConfiguration {
    var modelType: String = "base.en"
    var language: String = "en"
    
    func getModelPath() -> String {
        let fileManager = FileManager.default
        let appSupportURL = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dirURL = appSupportURL.appendingPathComponent("butler/Models/whisper")
        return dirURL.appendingPathComponent("ggml-\(modelType).bin").path
    }
}
