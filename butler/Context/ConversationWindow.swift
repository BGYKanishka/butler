import Foundation

class ConversationWindow {
    let windowDuration: TimeInterval
    let maxTokens: Int
    
    init(duration: TimeInterval = 300, maxTokens: Int = 4096) {
        self.windowDuration = duration
        self.maxTokens = maxTokens
    }
    
    func filterRecent(turns: [ConversationTurn]) -> [ConversationTurn] {
        let now = Date()
        var window: [ConversationTurn] = []
        
        for turn in turns.reversed() {
            let age = now.timeIntervalSince(turn.timestamp)
            if age <= windowDuration && window.count < 30 {
                window.insert(turn, at: 0)
            } else {
                break
            }
        }
        
        return window
    }
}
