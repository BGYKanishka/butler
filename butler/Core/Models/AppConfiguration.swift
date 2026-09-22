import Foundation

enum ConfigKey {
    static let whisperModelPath = "whisperModelPath"
    static let llamaModelPath = "llamaModelPath"
    static let llmTemperature = "llmTemperature"
    static let llmMaxTokens = "llmMaxTokens"
    static let isVisionEnabled = "isVisionEnabled"
    static let selectedMicrophoneID = "selectedMicrophoneID"
    static let saveTranscripts = "saveTranscripts"
    static let modelProfile = "modelProfile"
}

struct ModelConfiguration {
    let name: String
    let fileName: String
    let contextSize: Int
    let temperature: Float
    let maxTokens: Int
    let gpuLayers: Int
    let threads: Int
}

enum ModelProfile: String, CaseIterable {
    case fast, balanced, quality

    var configuration: ModelConfiguration {
        switch self {
        case .fast:
            return ModelConfiguration(name: "Fast", fileName: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
                                       contextSize: 8192, temperature: 0.3, maxTokens: 200, gpuLayers: 999, threads: 4)
        case .balanced:
            return ModelConfiguration(name: "Balanced", fileName: "Qwen2.5-7B-Instruct-Q4_K_M.gguf",
                                       contextSize: 8192, temperature: 0.3, maxTokens: 200, gpuLayers: 999, threads: 4)
        case .quality:
            return ModelConfiguration(name: "Quality", fileName: "Qwen2.5-14B-Instruct-Q4_K_M.gguf",
                                       contextSize: 8192, temperature: 0.3, maxTokens: 250, gpuLayers: 999, threads: 6)
        }
    }
}

