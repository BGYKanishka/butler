import ScreenCaptureKit
import Combine
import CoreMedia

class SystemAudioCaptureService: NSObject, AudioCaptureService, ObservableObject, SCStreamOutput, @unchecked Sendable {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    var onSamplesCaptured: (([Float]) -> Void)?
    var onAudioLevelChanged: ((Float) -> Void)?
    private var stream: SCStream?
    private var isStarting = false
    
    func start() async throws {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        
        // Bypass CGPreflightScreenCaptureAccess() due to Xcode ad-hoc signing bugs.
        // Missing permissions will throw and fallback to mic-only capture.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        
        // Captures all system audio. Future iterations may filter to specific meeting apps.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        // Include the app's own audio in the capture.
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 16000
        config.channelCount = 1
        
        // Use actual dimensions to prevent silent audio capture failures on some macOS versions.
        config.width = display.width
        config.height = display.height
        // Throttle frame rate (1 frame/hr) to suppress macOS dropped frame logs when video output is removed.
        config.minimumFrameInterval = CMTime(value: 3600, timescale: 1)
        
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "SystemAudioCaptureQueue"))
        
        try await stream?.startCapture()
        
        await MainActor.run {
            self.isRunning = true
        }
    }
    
    func stop() {
        guard isRunning else { return }
        // Clear the flag synchronously so that any concurrent stop() call is
        // blocked immediately — before the async teardown begins.
        isRunning = false
        let capturedStream = stream
        stream = nil
        Task {
            try? await capturedStream?.stopCapture()
            DispatchQueue.main.async {
                self.audioLevel = 0.0
                self.onAudioLevelChanged?(0.0)
            }
        }
    }
    
    private var audioConverter: AudioConverter?
    
    // ... inside stream method:
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDesc)
        
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0 else { return }
        
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount
        
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return }
        
        if audioConverter == nil {
            audioConverter = try? AudioConverter(from: format)
        }
        
        guard let outputBuffer = audioConverter?.convert(buffer: pcmBuffer) else { return }
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        
        let length = Int(outputBuffer.frameLength)
        var samples = [Float](repeating: 0.0, count: length)
        for i in 0..<length {
            let sample = channelData[i]
            samples[i] = (sample.isNaN || sample.isInfinite) ? 0.0 : sample
        }

        guard !samples.isEmpty else { return }
        onSamplesCaptured?(samples)

        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count)))
        onAudioLevelChanged?(rms)
        
        DispatchQueue.main.async {
            self.audioLevel = rms
        }
    }
}
