import Foundation

enum AssistantEvent {
    case audioCaptured(AudioChunk)
    case speechDetected(source: AudioSource)
    case transcriptUpdated(TranscriptSegment)
    case questionDetected(QuestionEvent)
    case llmTokenGenerated(String)
    case llmResponseCompleted
    case error(AssistantError)
}

struct QuestionEvent {
    let transcript: TranscriptSegment
    let confidence: Float
}

struct ConversationTurn {
    let id: UUID
    let source: AudioSource
    let text: String
    let timestamp: Date
}
