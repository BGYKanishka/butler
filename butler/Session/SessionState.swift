import Foundation

enum SessionState: Equatable {
    static func == (lhs: SessionState, rhs: SessionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening), (.processing, .processing), (.answering, .answering):
            return true
        case (.error, .error):
            return true // Simplified for Equatable
        default:
            return false
        }
    }
    case idle
    case listening
    case processing
    case answering
    case error(Error)
}
