import Foundation

class AudioSessionCoordinator {
    let micRingBuffer = AudioRingBuffer(capacity: 16000 * 60)
    let sysRingBuffer = AudioRingBuffer(capacity: 16000 * 60)
    
    let micVAD = VoiceActivityDetector()
    let sysVAD = VoiceActivityDetector()
    
    // Connect capture services to buffers
}
