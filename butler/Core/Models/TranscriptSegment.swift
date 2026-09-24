import Foundation

struct TranscriptSegment {
    let id: UUID
    let source: AudioSource
    let startTime: TimeInterval
    let endTime: TimeInterval
    var text: String
    var isFinal: Bool
    let confidence: Float?
}
