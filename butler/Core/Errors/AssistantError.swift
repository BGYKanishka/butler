import Foundation

enum AssistantError: Error {
    case permissionDenied(String)
    case initializationFailed(String)
    case modelNotFound(String)
    case inferenceFailed(String)
}
