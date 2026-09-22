import AVFoundation
import Combine

class MicrophoneCaptureService: AudioCaptureService, ObservableObject, @unchecked Sendable {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    
    var onSamplesCaptured: (([Float]) -> Void)?
    
    init() {
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
        
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            throw AssistantError.initializationFailed("Failed to create target format")
        }
        
        guard let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AssistantError.initializationFailed("Failed to create audio converter")
        }
        self.converter = audioConverter
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            // Calculate capacity for the converted buffer
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            // Add a small padding to the capacity just in case
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
            
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            
            var error: NSError?
            var inputConsumed = false
            let status = self.converter?.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            
            guard status != .error, error == nil else { return }
            
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
