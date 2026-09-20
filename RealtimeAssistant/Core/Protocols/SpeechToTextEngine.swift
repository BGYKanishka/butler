import Foundation

protocol SpeechToTextEngine {
    func load() async throws
    func unload()
    func transcribe(samples: [Float], sampleRate: Int) async throws
    func cancel()
}
