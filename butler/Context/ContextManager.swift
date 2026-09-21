import Foundation

actor ContextManager {
    private var turns: [ConversationTurn] = []
    private let maxWindow: TimeInterval = 60 // 60 seconds rolling window
    
    func addTurn(_ turn: ConversationTurn) {
        turns.append(turn)
        let now = Date()
        turns.removeAll { now.timeIntervalSince($0.timestamp) > maxWindow }
    }
    
    func getRecentContext() -> String {
        return turns.map { turn in
            let prefix = turn.source == .microphone ? "[LOCAL]:" : "[REMOTE]:"
            return "\(prefix) \(turn.text)"
        }.joined(separator: "\n")
    }
}
