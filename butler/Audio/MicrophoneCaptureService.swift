import AVFoundation
import Combine

class MicrophoneCaptureService: AudioCaptureService, ObservableObject {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private let engine = AVAudioEngine()
    
    var onSamplesCaptured: (([Float]) -> Void)?
    private var converter: AudioConverter?
    
    init() {}
    
    func start() async throws {
        guard !isRunning else { return }
        
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self = self else { return }
            
            if self.converter == nil {
                self.converter = try? AudioConverter()
            }
            
            guard let convertedBuffer = self.converter?.convert(buffer: buffer),
                  let channelData = convertedBuffer.floatChannelData?[0] else { return }
            
            let frameLength = Int(convertedBuffer.frameLength)
            var samples = [Float](repeating: 0.0, count: frameLength)
            
            var rms: Float = 0
            for i in 0..<frameLength {
                let sample = channelData[i]
                samples[i] = sample
                rms += sample * sample
            }
            rms = sqrt(rms / Float(frameLength))
            
            self.onSamplesCaptured?(samples)
            
            DispatchQueue.main.async {
                self.audioLevel = rms
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
