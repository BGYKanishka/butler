import Foundation

class ContextCompressor {
    func compress(turns: [ConversationTurn]) -> [ConversationTurn] {
        guard turns.count > 10 else { return turns }
        
        let recentIndex = turns.count - 10
        let recentTurns = Array(turns[recentIndex...])
        var compressedHistory: [ConversationTurn] = []
        
        for i in 0..<recentIndex {
            let turn = turns[i]
            if turn.type == .question || turn.type == .answer {
                compressedHistory.append(turn)
            } else if turn.text.count > 50 {
                compressedHistory.append(turn)
            }
        }
        
        return compressedHistory + recentTurns
    }
}
