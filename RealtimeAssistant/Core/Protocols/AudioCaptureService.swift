import Foundation

enum AudioSource {
    case microphone
    case system
}


protocol AudioCaptureService {
    var isRunning: Bool { get }
    func start() async throws
    func stop()
}
