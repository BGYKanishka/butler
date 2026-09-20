import Foundation

class AudioSessionCoordinator {
    let micRingBuffer = AudioRingBuffer()
    let sysRingBuffer = AudioRingBuffer()
    
    let micVAD = VoiceActivityDetector()
    let sysVAD = VoiceActivityDetector()
    
    // Connect capture services to buffers
}
