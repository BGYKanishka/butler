import Foundation

enum TurnType {
    case statement
    case question
    case answer
}

struct ConversationTurn {
    let id: UUID
    let source: AudioSource
    let type: TurnType
    let text: String
    let timestamp: Date
}
