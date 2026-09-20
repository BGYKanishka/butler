import AVFoundation
import Combine

class MicrophoneCaptureService: AudioCaptureService, ObservableObject {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private let engine = AVAudioEngine()
    
    init() {}
    
    func start() async throws {
        guard !isRunning else { return }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            if let channelData = buffer.floatChannelData?[0] {
                let frameLength = Int(buffer.frameLength)
                var rms: Float = 0
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    rms += sample * sample
                }
                rms = sqrt(rms / Float(frameLength))
                
                DispatchQueue.main.async {
                    self.audioLevel = rms
                }
            }
        }
        
        engine.prepare()
        try engine.start()
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }
    
    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.audioLevel = 0.0
        }
    }
}
