import Foundation

protocol LLMEngine {
    func load() async throws
    func unload() async
    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws
    func generateVisionStreaming(prompt: String, imagePath: String, onToken: @escaping (String) -> Void) async throws
    func saveState(to path: String, prompt: String) async throws
    func loadState(from path: String) async throws
    func cancel()
}
