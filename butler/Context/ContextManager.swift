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
    
    func getRecentTurns() -> [ConversationTurn] {
        return turns
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
    
    /// Returns the most recent user or system audio query that has not yet been answered by the assistant,
    /// provided it occurred within `timeInterval` seconds.
    func getUnansweredUserQuery(within timeInterval: TimeInterval = 60) -> String? {
        let now = Date()
        let recentTurns = turns.filter { now.timeIntervalSince($0.timestamp) <= timeInterval }
        
        let lastAnswerIndex = recentTurns.lastIndex(where: { $0.source == .assistant })
        
        let pendingUserTurns: [ConversationTurn]
        if let lastAnswerIndex = lastAnswerIndex {
            pendingUserTurns = Array(recentTurns.suffix(from: recentTurns.index(after: lastAnswerIndex)))
                .filter { ($0.source == .microphone || $0.source == .system) && $0.text != "[Image Analyzed]" }
        } else {
            pendingUserTurns = recentTurns.filter { ($0.source == .microphone || $0.source == .system) && $0.text != "[Image Analyzed]" }
        }
        
        guard !pendingUserTurns.isEmpty else { return nil }
        
        return pendingUserTurns.map { "\($0.source == .microphone ? "User" : "Other party"): \($0.text)" }.joined(separator: "\n")
    }
}
