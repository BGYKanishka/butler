import Foundation
import Combine

class AudioSessionCoordinator: @unchecked Sendable {
    var micService: any AudioCaptureService
    var sysAudioService: any AudioCaptureService
    
    let micVAD = VoiceActivityDetector()
    let sysVAD = VoiceActivityDetector()
    
    let micRingBuffer = AudioRingBuffer(capacity: 320000)
    let sysRingBuffer = AudioRingBuffer(capacity: 320000)
    
    private let vadQueue = DispatchQueue(label: "com.butler.vadQueue", qos: .userInitiated)
    private var vadTimer: DispatchSourceTimer?
    private var isRunning = false
    
    @Published var systemAudioAvailable = false
    @Published var micAudioLevel: Float = 0.0
    @Published var sysAudioLevel: Float = 0.0
    
    private var speechStartTimestamp: TimeInterval?
    private var sysSpeechStartTimestamp: TimeInterval?
    private var prevMicSpeaking = false
    private var prevSysSpeaking = false
    
    var onSpeechDetected: (([Float], AudioSource) -> Void)?
    
    init(micService: any AudioCaptureService, sysAudioService: any AudioCaptureService) {
        self.micService = micService
        self.sysAudioService = sysAudioService
        
        setupBindings()
    }
    
    private func setupBindings() {
        micService.onSamplesCaptured = { [weak self] samples in
            self?.micRingBuffer.push(samples, timestamp: mach_absolute_time())
        }
        micService.onAudioLevelChanged = { [weak self] level in
            DispatchQueue.main.async { self?.micAudioLevel = level }
        }
        
        sysAudioService.onSamplesCaptured = { [weak self] samples in
            self?.sysRingBuffer.push(samples, timestamp: mach_absolute_time())
        }
        sysAudioService.onAudioLevelChanged = { [weak self] level in
            DispatchQueue.main.async { self?.sysAudioLevel = level }
        }
    }
    
    func start(includeSystemAudio: Bool = true, micGranted: Bool = true) async throws {
        if micGranted {
            do {
                try await micService.start()
            } catch {
                print("Session Warning: Microphone start failed: \(error)")
            }
        }
        
        if includeSystemAudio {
            do {
                try await sysAudioService.start()
                DispatchQueue.main.async { self.systemAudioAvailable = true }
            } catch {
                print("System audio capture failed, continuing with microphone only: \(error)")
                DispatchQueue.main.async { self.systemAudioAvailable = false }
            }
        } else {
            DispatchQueue.main.async { self.systemAudioAvailable = false }
        }
        
        isRunning = true
        startVADPolling()
    }
    
    func stop() {
        micService.stop()
        sysAudioService.stop()
        isRunning = false
        stopVADPolling()
    }
    
    private func startVADPolling() {
        vadTimer = DispatchSource.makeTimerSource(queue: vadQueue)
        vadTimer?.schedule(deadline: .now(), repeating: 0.1)
        vadTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.processVAD(for: .microphone, ringBuffer: self.micRingBuffer, vad: self.micVAD, prevSpeaking: &self.prevMicSpeaking, startTimestamp: &self.speechStartTimestamp)
            self.processVAD(for: .system, ringBuffer: self.sysRingBuffer, vad: self.sysVAD, prevSpeaking: &self.prevSysSpeaking, startTimestamp: &self.sysSpeechStartTimestamp)
        }
        vadTimer?.resume()
    }
    
    private func stopVADPolling() {
        vadTimer?.cancel()
        vadTimer = nil
    }
    
    private func processVAD(for source: AudioSource, ringBuffer: AudioRingBuffer, vad: VoiceActivityDetector, prevSpeaking: inout Bool, startTimestamp: inout TimeInterval?) {
        let samples = ringBuffer.getRecent(samplesCount: 1600)
        guard !samples.isEmpty else { return }
        
        let rms = calculateRMS(samples)
        let ts = Date().timeIntervalSince1970
        let isSpeaking = vad.process(rms: rms, timestamp: ts)
        
        let justEnded = !isSpeaking && prevSpeaking
        let justStarted = isSpeaking && !prevSpeaking
        prevSpeaking = isSpeaking
        
        let sourceName = source == .microphone ? "Mic" : "SystemAudio"
        
        if justStarted { 
            print("VAD Info: Speech started on \(sourceName) (RMS: \(rms))")
            startTimestamp = ts 
        }
        if justEnded, let start = startTimestamp {
            print("VAD Info: Speech ended on \(sourceName). Capturing segment...")
            startTimestamp = nil
            let duration = ts - start
            guard duration > 1.0 else { return }
            let count = Int(duration * 16000)
            let captured = ringBuffer.getRecent(samplesCount: count)
            onSpeechDetected?(captured, source)
        }
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }
}
