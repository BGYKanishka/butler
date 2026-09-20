import Foundation

protocol LLMEngine {
    func load() async throws
    func unload()
    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws
    func cancel()
}

struct AnswerToken {
    let text: String
}
