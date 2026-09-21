import AVFoundation
import Combine

class MicrophoneCaptureService: AudioCaptureService, ObservableObject, @unchecked Sendable {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    
    var onSamplesCaptured: (([Float]) -> Void)?
    
    init() {
        engine.attach(mixer)
    }
    
    func start() async throws {
        guard !isRunning else { return }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Connect input to mixer
        engine.connect(inputNode, to: mixer, format: inputFormat)
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw AssistantError.initializationFailed("Failed to create target format")
        }
        
        // Connect mixer to main mixer to establish the graph for conversion
        let mainMixer = engine.mainMixerNode
        engine.connect(mixer, to: mainMixer, format: targetFormat)
        
        // Mute the mixer so we don't hear microphone feedback
        mixer.outputVolume = 0.0
        
        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: targetFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            
            let frameLength = Int(buffer.frameLength)
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
        mixer.removeTap(onBus: 0)
        engine.stop()
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.audioLevel = 0.0
        }
    }
}
