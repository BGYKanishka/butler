import Foundation

struct AudioChunk {
    let id: UUID
    let source: AudioSource
    let timestampNanoseconds: UInt64
    let sampleRate: Int
    let channels: Int
    let samples: [Float]
}
