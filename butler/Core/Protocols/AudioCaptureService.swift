import Foundation

enum AudioSource {
    case microphone
    case system
}


protocol AudioCaptureService {
    var isRunning: Bool { get }
    var audioLevel: Float { get }
    var onSamplesCaptured: (([Float]) -> Void)? { get set }
    var onAudioLevelChanged: ((Float) -> Void)? { get set }
    
    func start() async throws
    func stop()
}
