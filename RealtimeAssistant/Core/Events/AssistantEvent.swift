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
