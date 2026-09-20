import Foundation

class LatencyTracker {
    private var events: [String: Date] = [:]
    
    func markEvent(_ name: String) {
        events[name] = Date()
    }
    
    func timeSince(_ name: String) -> TimeInterval? {
        guard let start = events[name] else { return nil }
        return Date().timeIntervalSince(start)
    }
}
