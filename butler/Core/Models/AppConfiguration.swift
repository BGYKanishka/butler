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

/// Parameters for a single model variant.
///
/// `gpuLayers` and `threads` are defined here for future use — when
/// `LlamaWrapper` exposes them via `llama_context_params` they should be
/// plumbed through rather than hardcoded inside the wrapper.
struct ModelConfiguration {
    let name: String
    let fileName: String
    let contextSize: Int
    let temperature: Float
    let maxTokens: Int
    let gpuLayers: Int
    let threads: Int
}

/// Profiles differ only in context window and token budget.
///
/// All three currently reference the same GGUF file because only one
/// quantisation is shipped at launch. When additional quants are bundled
/// (e.g. Q2_K for fast, Q8_0 for quality), update `fileName` per case and
/// wire `gpuLayers` / `threads` into `llama_context_params` inside
/// `LlamaWrapper.loadModel`.
enum ModelProfile: String, CaseIterable {
    case fast, balanced, quality

    var configuration: ModelConfiguration {
        switch self {
        case .fast:
            // Smallest context window — fastest cold-start and lowest peak memory.
            return ModelConfiguration(name: "Fast", fileName: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf",
                                       contextSize: 8192, temperature: 0.3, maxTokens: 200, gpuLayers: 999, threads: 4)
        case .balanced:
            // 16 k context fits most interview conversations without truncation.
            return ModelConfiguration(name: "Balanced", fileName: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf",
                                       contextSize: 16384, temperature: 0.3, maxTokens: 200, gpuLayers: 999, threads: 4)
        case .quality:
            // 32 k context + higher token budget for detailed multi-step answers.
            return ModelConfiguration(name: "Quality", fileName: "Qwen_Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf",
                                       contextSize: 32768, temperature: 0.3, maxTokens: 250, gpuLayers: 999, threads: 6)
        }
    }
}
