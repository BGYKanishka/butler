import Foundation

protocol LLMEngine {
    func load() async throws
    func unload() async
    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws
    func generateVisionStreaming(prompt: String, imagePath: String, onToken: @escaping (String) -> Void) async throws
    func cancel()
}
