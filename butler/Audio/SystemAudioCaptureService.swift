import ScreenCaptureKit
import Combine
import CoreMedia

class SystemAudioCaptureService: NSObject, AudioCaptureService, ObservableObject, SCStreamOutput, @unchecked Sendable {
    @Published var isRunning: Bool = false
    @Published var audioLevel: Float = 0.0
    
    var onSamplesCaptured: (([Float]) -> Void)?
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
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        
        // Add minimal video settings and a video output to suppress the 
        // `_SCStream_RemoteVideoQueueOperationHandlerWithError` console spam
        config.width = 16
        config.height = 16
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "SystemAudioCaptureQueue"))
        try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "SystemAudioCaptureQueue"))
        
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
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        // Query required size first
        var ablSize = 0
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: &ablSize,
            bufferListOut: nil, bufferListSize: 0,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: nil)

        guard ablSize > 0 else { return }
        let ablPtr = UnsafeMutableRawPointer.allocate(byteCount: ablSize, alignment: 16)
        defer { ablPtr.deallocate() }

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer, bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr.assumingMemoryBound(to: AudioBufferList.self),
            bufferListSize: ablSize,
            blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer)
        guard status == noErr else { return }

        let abl = ablPtr.assumingMemoryBound(to: AudioBufferList.self)
        let mBuffers = abl.pointee.mBuffers
        guard let data = mBuffers.mData, mBuffers.mDataByteSize > 0 else { return }

        let frameCount = Int(mBuffers.mDataByteSize) / MemoryLayout<Float>.size
        let samples = Array(UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: Float.self),
            count: frameCount))

        onSamplesCaptured?(samples)

        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count)))
        DispatchQueue.main.async { self.audioLevel = rms }
    }
}
