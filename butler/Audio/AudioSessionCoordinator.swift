import Foundation
import Combine

class AudioSessionCoordinator: @unchecked Sendable {
    let micService: MicrophoneCaptureService
    let sysAudioService: SystemAudioCaptureService
    
    let micVAD = VoiceActivityDetector()
    let sysVAD = VoiceActivityDetector()
    
    let micRingBuffer = AudioRingBuffer(capacity: 320000)
    let sysRingBuffer = AudioRingBuffer(capacity: 320000)
    
    private let vadQueue = DispatchQueue(label: "com.butler.vadQueue", qos: .userInitiated)
    private var vadTimer: DispatchSourceTimer?
    private var isRunning = false
    
    @Published var systemAudioAvailable = false
    
    private var speechStartTimestamp: TimeInterval?
    private var sysSpeechStartTimestamp: TimeInterval?
    private var prevMicSpeaking = false
    private var prevSysSpeaking = false
    
    var onSpeechDetected: (([Float], AudioSource) -> Void)?
    
    init(micService: MicrophoneCaptureService, sysAudioService: SystemAudioCaptureService) {
        self.micService = micService
        self.sysAudioService = sysAudioService
        
        setupBindings()
    }
    
    private func setupBindings() {
        micService.onSamplesCaptured = { [weak self] samples in
            self?.micRingBuffer.push(samples, timestamp: mach_absolute_time())
        }
        
        sysAudioService.onSamplesCaptured = { [weak self] samples in
            self?.sysRingBuffer.push(samples, timestamp: mach_absolute_time())
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
            self?.processMicVAD()
            self?.processSysVAD()
        }
        vadTimer?.resume()
    }
    
    private func stopVADPolling() {
        vadTimer?.cancel()
        vadTimer = nil
    }
    
    private func processMicVAD() {
        let samples = micRingBuffer.getRecent(samplesCount: 1600)
        guard !samples.isEmpty else { return }
        
        let rms = calculateRMS(samples)
        let ts = Date().timeIntervalSince1970
        let isSpeaking = micVAD.process(rms: rms, timestamp: ts)
        
        let justEnded = !isSpeaking && prevMicSpeaking
        let justStarted = isSpeaking && !prevMicSpeaking
        prevMicSpeaking = isSpeaking
        
        if justStarted { 
            print("VAD Info: Speech started on Mic (RMS: \(rms))")
            speechStartTimestamp = ts 
        }
        if justEnded, let start = speechStartTimestamp {
            print("VAD Info: Speech ended on Mic. Capturing segment...")
            speechStartTimestamp = nil
            let duration = ts - start
            guard duration > 0.5 else { return }
            let count = Int(duration * 16000)
            let captured = micRingBuffer.getRecent(samplesCount: count)
            onSpeechDetected?(captured, .microphone)
        }
    }
    
    private func processSysVAD() {
        let samples = sysRingBuffer.getRecent(samplesCount: 1600)
        guard !samples.isEmpty else { return }
        
        let rms = calculateRMS(samples)
        let ts = Date().timeIntervalSince1970
        let isSpeaking = sysVAD.process(rms: rms, timestamp: ts)
        
        let justEnded = !isSpeaking && prevSysSpeaking
        let justStarted = isSpeaking && !prevSysSpeaking
        prevSysSpeaking = isSpeaking
        
        if justStarted { 
            print("VAD Info: Speech started on SystemAudio (RMS: \(rms))")
            sysSpeechStartTimestamp = ts 
        }
        if justEnded, let start = sysSpeechStartTimestamp {
            print("VAD Info: Speech ended on SystemAudio. Capturing segment...")
            sysSpeechStartTimestamp = nil
            let duration = ts - start
            guard duration > 0.5 else { return }
            let count = Int(duration * 16000)
            let captured = sysRingBuffer.getRecent(samplesCount: count)
            onSpeechDetected?(captured, .system)
        }
    }
    
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }
}
