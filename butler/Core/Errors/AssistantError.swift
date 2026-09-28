import Foundation

/// Domain-specific errors surfaced throughout the assistant pipeline.
///
/// Conforms to `LocalizedError` so that `error.localizedDescription` and
/// SwiftUI's default error presentation show readable sentences rather than
/// raw enum case names.
enum AssistantError: LocalizedError {

    // MARK: - Model lifecycle

    /// A required model file could not be found at the expected path.
    case modelNotFound(String)

    /// The model file exists but failed to load (bad format, OOM, etc.).
    case modelLoadFailed(String)

    // MARK: - Inference

    /// The engine is in a state where it cannot accept inference requests.
    case inferenceFailed(String)

    // MARK: - Initialisation

    /// A subsystem failed to initialise (audio session, Whisper context, etc.).
    case initializationFailed(String)

    // MARK: - Permissions

    /// The user has not granted a required system permission.
    case permissionDenied(String)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let detail):
            return "Model not found — \(detail)"
        case .modelLoadFailed(let detail):
            return "Failed to load model — \(detail)"
        case .inferenceFailed(let detail):
            return "Inference error — \(detail)"
        case .initializationFailed(let detail):
            return "Initialisation failed — \(detail)"
        case .permissionDenied(let permission):
            return "Permission not granted: \(permission)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotFound:
            return "Open Settings and re-download the model files."
        case .modelLoadFailed:
            return "The model file may be corrupt. Try re-downloading it from Settings."
        case .inferenceFailed:
            return "Stop the session and start again. If the problem persists, reload the model."
        case .initializationFailed:
            return "Restart the app. If the problem continues, check the system audio settings."
        case .permissionDenied(let permission):
            return "Grant '\(permission)' access in System Settings → Privacy & Security."
        }
    }
}
