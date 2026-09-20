import Foundation

struct ConversationTurn {
    let id: UUID
    let source: AudioSource
    let text: String
    let timestamp: Date
}
