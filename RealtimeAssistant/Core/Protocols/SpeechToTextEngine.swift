import Foundation

protocol SpeechToTextEngine {
    func load() async throws
    func unload()
    func transcribe(samples: [Float], sampleRate: Int) async throws
    func cancel()
}

struct TranscriptSegment {
    let id: UUID
    let source: AudioSource
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let isFinal: Bool
    let confidence: Float?
}
