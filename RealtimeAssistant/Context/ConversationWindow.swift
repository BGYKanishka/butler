import Foundation

class ConversationWindow {
    let windowDuration: TimeInterval
    
    init(duration: TimeInterval = 60) {
        self.windowDuration = duration
    }
    
    func filterRecent(turns: [ConversationTurn]) -> [ConversationTurn] {
        let now = Date()
        return turns.filter { now.timeIntervalSince($0.timestamp) <= windowDuration }
    }
}
