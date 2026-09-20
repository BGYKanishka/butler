import Foundation

struct TranscriptSegment {
    let id: UUID
    let source: AudioSource
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let isFinal: Bool
    let confidence: Float?
}
