import Foundation

struct LLMConfiguration {
    var contextSize: Int = 8192
    
    var temperature: Float {
        let val = UserDefaults.standard.double(forKey: "llmTemperature")
        return val > 0 ? Float(val) : 0.3
    }
    
    var maxTokens: Int {
        let val = UserDefaults.standard.integer(forKey: "llmMaxTokens")
        return val > 0 ? val : 200
    }
    
    var modelFileName: String = "Llama-3.2-3B-Instruct.gguf"
    
    func getModelPath() -> String {
        let customPath = UserDefaults.standard.string(forKey: "llamaModelPath") ?? ""
        if !customPath.isEmpty {
            return customPath
        }
        
        guard let appSupportURL = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return "" }
        let dirURL = appSupportURL.appendingPathComponent("RealtimeAssistant/Models/llm")
        return dirURL.appendingPathComponent(modelFileName).path
    }
}
