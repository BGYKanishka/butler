import ScreenCaptureKit
import Combine
import CoreMedia

class SystemAudioCaptureService: NSObject, AudioCaptureService, ObservableObject, SCStreamOutput {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    var onSamplesCaptured: (([Float]) -> Void)?
    private var stream: SCStream?
    
    func start() async throws {
        guard !isRunning else { return }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "SystemAudioCaptureQueue"))
        
        try await stream?.startCapture()
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }
    
    func stop() {
        guard isRunning else { return }
        
        Task {
            try? await stream?.stopCapture()
            DispatchQueue.main.async {
                self.isRunning = false
                self.audioLevel = 0.0
            }
        }
    }
    
    private let converter = AudioConverter()!
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)) else { return }
        
        // Copy data to pcmBuffer
        for channel in 0..<Int(audioFormat.channelCount) {
            if let dest = pcmBuffer.floatChannelData?[channel], let src = audioBufferList.mBuffers.mData {
                // Warning: this assumes the SCStream is giving us Float32. 
                // A robust solution uses vDSP or checks the bit depth, but SCK audio is Float32 by default.
                memcpy(dest, src, Int(audioBufferList.mBuffers.mDataByteSize))
            }
        }
        pcmBuffer.frameLength = AVAudioFrameCount(sampleBuffer.numSamples)
        
        guard let convertedBuffer = converter.convert(buffer: pcmBuffer),
              let channelData = convertedBuffer.floatChannelData?[0] else { return }
        
        let frameLength = Int(convertedBuffer.frameLength)
        var samples = [Float](repeating: 0.0, count: frameLength)
        var rms: Float = 0
        
        for i in 0..<frameLength {
            let sample = channelData[i]
            samples[i] = sample
            rms += sample * sample
        }
        
        if frameLength > 0 {
            self.onSamplesCaptured?(samples)
            
            rms = sqrt(rms / Float(frameLength))
            DispatchQueue.main.async {
                self.audioLevel = rms
            }
        }
    }
}
