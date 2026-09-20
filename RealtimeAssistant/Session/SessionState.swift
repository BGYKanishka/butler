import Foundation

enum SessionState {
    case idle
    case initializing
    case active
    case stopping
    case error(Error)
}
