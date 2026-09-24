import Foundation

enum AudioSource: Codable, Equatable {
    case microphone
    case system
    case assistant
}


protocol AudioCaptureService {
    var isRunning: Bool { get }
    var audioLevel: Float { get }
    var onSamplesCaptured: (([Float]) -> Void)? { get set }
    var onAudioLevelChanged: ((Float) -> Void)? { get set }
    
    func start() async throws
    func stop()
}
