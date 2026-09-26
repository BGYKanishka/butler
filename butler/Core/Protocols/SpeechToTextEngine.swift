import Foundation

protocol SpeechToTextEngine {
    func load() async throws
    func unload() async
    func transcribe(samples: [Float], sampleRate: Int, source: AudioSource) async throws
    func cancel()
}
