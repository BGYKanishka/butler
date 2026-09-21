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
    
    var modelFileName: String = "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
    
    func getModelPath() -> String {
        let customPath = UserDefaults.standard.string(forKey: "llamaModelPath") ?? ""
        if !customPath.isEmpty {
            return customPath
        }
        
        return Constants.llmModelPath ?? ""
    }
}
