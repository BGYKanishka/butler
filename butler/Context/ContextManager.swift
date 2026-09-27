import Foundation

actor ContextManager {
    private var turns: [ConversationTurn] = []
    private let maxWindow: TimeInterval = 600 // 10 minutes rolling window for huge conversations
    private let maxTurns: Int = 100 // retain up to 100 turns to identify problems
    
    func addTurn(_ turn: ConversationTurn) {
        turns.append(turn)
        let now = Date()
        turns.removeAll { now.timeIntervalSince($0.timestamp) > maxWindow }
        if turns.count > maxTurns {
            turns.removeFirst(turns.count - maxTurns)
        }
    }
    
    func getRecentContext() -> String {
        return turns.map { turn in
            let prefix: String
            switch turn.source {
            case .microphone: prefix = "[CANDIDATE (USER)]:"
            case .system: prefix = "[INTERVIEWER]:"
            case .assistant: prefix = "[ASSISTANT]:"
            }
            return "\(prefix) \(turn.text)"
        }.joined(separator: "\n")
    }
}
