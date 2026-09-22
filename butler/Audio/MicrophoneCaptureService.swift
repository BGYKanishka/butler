import AVFoundation
import Combine

class MicrophoneCaptureService: AudioCaptureService, ObservableObject, @unchecked Sendable {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var sinkNode: AVAudioSinkNode?
    
    var onSamplesCaptured: (([Float]) -> Void)?
    
    init() {
        engine.attach(mixer)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange, object: engine)
    }
    
    @objc private func handleConfigurationChange() {
        guard isRunning else { return }
        engine.stop()
        Task { try? await start() }
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
        
        let maxFrames: AVAudioFrameCount = 4096
        inputNode.auAudioUnit.maximumFramesToRender = maxFrames
        mixer.auAudioUnit.maximumFramesToRender = maxFrames
        
        // Create the sink node to receive the converted audio
        let sink = AVAudioSinkNode { [weak self] (timestamp, frameCount, audioBufferList) -> OSStatus in
            guard let self = self else { return noErr }
            let mutableABL = UnsafeMutablePointer<AudioBufferList>(mutating: audioBufferList)
            let abl = UnsafeMutableAudioBufferListPointer(mutableABL)
            guard let buffer = abl.first else { return noErr }
            
            let frameLength = Int(frameCount)
            var samples = [Float](repeating: 0.0, count: frameLength)
            var rms: Float = 0
            
            if let data = buffer.mData {
                let floatData = data.assumingMemoryBound(to: Float.self)
                for i in 0..<frameLength {
                    let sample = floatData[i]
                    samples[i] = sample
                    rms += sample * sample
                }
            }
            
            rms = sqrt(rms / Float(max(1, frameLength)))
            
            self.onSamplesCaptured?(samples)
            
            DispatchQueue.main.async {
                self.audioLevel = rms
            }
            return noErr
        }
        
        self.sinkNode = sink
        engine.attach(sink)
        
        // Connect the graph: input -> mixer -> sink
        // The mixer handles the format conversion from inputFormat (48000Hz) to targetFormat (16000Hz)
        engine.connect(mixer, to: sink, format: targetFormat)
        
        engine.prepare()
        try engine.start()
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }
    
    func stop() {
        guard isRunning else { return }
        engine.stop()
        if let sink = sinkNode {
            engine.detach(sink)
            sinkNode = nil
        }
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.audioLevel = 0.0
        }
    }
}
