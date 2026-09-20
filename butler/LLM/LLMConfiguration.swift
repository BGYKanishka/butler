import Foundation

struct LLMConfiguration {
    var contextSize: Int = 8192
    var temperature: Float = 0.3
    var maxTokens: Int = 200
    var modelFileName: String = "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"
    
    func getModelPath() -> String {
        let fileManager = FileManager.default
        let appSupportURL = try! fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dirURL = appSupportURL.appendingPathComponent("butler/Models/llm")
        return dirURL.appendingPathComponent(modelFileName).path
    }
}
