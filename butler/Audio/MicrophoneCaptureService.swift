import AVFoundation
import Combine

class MicrophoneCaptureService: AudioCaptureService, ObservableObject, @unchecked Sendable {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private var engine = AVAudioEngine()
    private var converter: AudioConverter?
    
    var onSamplesCaptured: (([Float]) -> Void)?
    var onAudioLevelChanged: ((Float) -> Void)?
    
    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleConfigurationChange),
            name: .AVAudioEngineConfigurationChange, object: engine)
    }
    
    @objc private func handleConfigurationChange() {
        guard isRunning else { return }
        self.stop() // Must remove tap and reset state
        Task {
            // Give CoreAudio / Bluetooth a moment to settle the new format
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Recreate the engine entirely to avoid stale hardware formats
            DispatchQueue.main.async {
                NotificationCenter.default.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: self.engine)
                self.engine = AVAudioEngine()
                NotificationCenter.default.addObserver(self, selector: #selector(self.handleConfigurationChange), name: .AVAudioEngineConfigurationChange, object: self.engine)
                
                Task {
                    try? await self.start()
                }
            }
        }
    }
    
    func start() async throws {
        guard !isRunning else { return }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AssistantError.initializationFailed("Invalid microphone format (channels: \(inputFormat.channelCount), sampleRate: \(inputFormat.sampleRate)). Please check your Bluetooth connection.")
        }
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw AssistantError.initializationFailed("Failed to create target format")
        }
        
        self.converter = try AudioConverter(from: nil)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            guard let outputBuffer = self.converter?.convert(buffer: buffer) else { return }
            
            let frameLength = Int(outputBuffer.frameLength)
            var samples = [Float](repeating: 0.0, count: frameLength)
            var rms: Float = 0
            
            if let channelData = outputBuffer.floatChannelData?[0] {
                for i in 0..<frameLength {
                    let sample = channelData[i]
                    samples[i] = sample
                    rms += sample * sample
                }
            }
            
            rms = sqrt(rms / Float(max(1, frameLength)))
            self.onSamplesCaptured?(samples)
            self.onAudioLevelChanged?(rms)
            
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
            self.onAudioLevelChanged?(0.0)
        }
    }
}
