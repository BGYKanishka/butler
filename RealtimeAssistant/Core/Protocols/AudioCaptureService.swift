import Foundation

enum AudioSource {
    case microphone
    case system
}

struct AudioChunk {
    let id: UUID
    let source: AudioSource
    let timestampNanoseconds: UInt64
    let sampleRate: Int
    let channels: Int
    let samples: [Float]
}

protocol AudioCaptureService {
    var isRunning: Bool { get }
    func start() async throws
    func stop()
}
