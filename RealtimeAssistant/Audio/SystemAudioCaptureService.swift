import ScreenCaptureKit
import Combine
import CoreMedia

class SystemAudioCaptureService: NSObject, AudioCaptureService, ObservableObject, SCStreamOutput {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private var stream: SCStream?
    
    func start() async throws {
        guard !isRunning else { return }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        
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
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        
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
        
        let buffers = UnsafeBufferPointer<AudioBuffer>(start: &audioBufferList.mBuffers, count: Int(audioBufferList.mNumberBuffers))
        
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let pointer = data.assumingMemoryBound(to: Float.self)
            let frameLength = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            
            var rms: Float = 0
            for i in 0..<frameLength {
                let sample = pointer[i]
                rms += sample * sample
            }
            if frameLength > 0 {
                rms = sqrt(rms / Float(frameLength))
                DispatchQueue.main.async {
                    self.audioLevel = rms
                }
            }
        }
    }
}
