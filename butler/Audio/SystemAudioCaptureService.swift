import ScreenCaptureKit
import Combine
import CoreMedia

class SystemAudioCaptureService: NSObject, AudioCaptureService, ObservableObject, SCStreamOutput, @unchecked Sendable {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    var onSamplesCaptured: (([Float]) -> Void)?
    var onAudioLevelChanged: ((Float) -> Void)?
    private var stream: SCStream?
    
    func start() async throws {
        guard !isRunning else { return }
        
        // Note: We intentionally do NOT guard with CGPreflightScreenCaptureAccess() here.
        // CGPreflight returns false when running from Xcode with ad-hoc code signing,
        // even when the user has granted permission in System Settings. Instead, we let
        // SCShareableContent.excludingDesktopWindows throw if permission is truly denied.
        // AudioSessionCoordinator catches this and falls back to mic-only capture.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        
        // Note: Currently, we exclude no applications and no windows, which means we capture
        // the entire display's audio output (including notifications and other apps). 
        // This is a known privacy consideration for V1. Future iterations may filter to specific meeting apps.
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        // If set to true, the app ignores its own audio, making the test track invisible to system audio capture.
        config.excludesCurrentProcessAudio = false
        config.sampleRate = 16000
        config.channelCount = 1
        
        // Use the display's actual dimensions. Some macOS versions silently fail 
        // to capture audio if the width and height are too small (e.g., 1x1).
        config.width = display.width
        config.height = display.height
        // Set minimumFrameInterval to an extremely large value (1 frame per hour).
        // Since we removed the .screen output to avoid capturing video, macOS complains internally
        // about dropping frames. By throttling the frame rate, we stop the infinite log loop.
        config.minimumFrameInterval = CMTime(value: 3600, timescale: 1)
        
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
