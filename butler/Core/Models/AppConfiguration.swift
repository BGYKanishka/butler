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
    static let whisperVocabulary = "whisperVocabulary"
    static let projectPaths = "projectPaths"
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
            return ModelConfiguration(name: "Fast", fileName: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf",
                                       contextSize: 8192, temperature: 0.3, maxTokens: 200, gpuLayers: 999, threads: 4)
        case .balanced:
            return ModelConfiguration(name: "Balanced", fileName: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf",
                                       contextSize: 16384, temperature: 0.3, maxTokens: 200, gpuLayers: 999, threads: 4)
        case .quality:
            return ModelConfiguration(name: "Quality", fileName: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf",
                                       contextSize: 32768, temperature: 0.3, maxTokens: 250, gpuLayers: 999, threads: 6)
        }
    }
}

