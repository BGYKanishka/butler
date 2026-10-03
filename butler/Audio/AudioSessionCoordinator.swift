import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.butler", category: "Audio")

// VAD state runs exclusively on vadQueue. @Published properties update via DispatchQueue.main.
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

    // MARK: - VAD tuning
    private enum VAD {
        static let pollInterval: TimeInterval = 0.1    // seconds between VAD ticks
      
        static let preRollTime: TimeInterval  = 1.0
        static let overlapTime: TimeInterval  = 1.5    // overlap kept when force-slicing
        static let forceSliceAfter: TimeInterval = 10.0 // maximum continuous-speech window
        static let minimumDuration: TimeInterval = 1.0  // ignore segments shorter than this
        static let rmsWindowSamples: Int = 1600         // ~0.1 s at 16 kHz
    }
    
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
        
        // System audio is often lower amplitude but has less noise.
        // Lower the VAD threshold significantly so it doesn't miss speech.
        self.sysVAD.speechThreshold = 0.005
        self.sysVAD.silenceThreshold = 0.003
        
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
                logger.warning("Microphone start failed: \(error.localizedDescription)")
            }
        }
        
        if includeSystemAudio {
            do {
                try await sysAudioService.start()
                DispatchQueue.main.async { self.systemAudioAvailable = true }
            } catch {
                logger.warning("System audio capture failed — continuing with microphone only: \(error.localizedDescription)")
                DispatchQueue.main.async { self.systemAudioAvailable = false }
            }
        } else {
            DispatchQueue.main.async { self.systemAudioAvailable = false }
        }
        
        isRunning = true
        startVADPolling()
    }
    
    func stopMic() {
        micService.stop()
    }
    
    func stopSystemAudio() {
        sysAudioService.stop()
    }
    
    func stop() {
        micService.stop()
        sysAudioService.stop()
        isRunning = false
        stopVADPolling()
    }
    
    private func startVADPolling() {
        vadTimer = DispatchSource.makeTimerSource(queue: vadQueue)
        vadTimer?.schedule(deadline: .now(), repeating: VAD.pollInterval)
        vadTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.processVAD(for: .microphone, ringBuffer: self.micRingBuffer, vad: self.micVAD, prevSpeaking: &self.prevMicSpeaking, startTimestamp: &self.speechStartTimestamp, lastWritten: &self.lastMicWritten)
            self.processVAD(for: .system, ringBuffer: self.sysRingBuffer, vad: self.sysVAD, prevSpeaking: &self.prevSysSpeaking, startTimestamp: &self.sysSpeechStartTimestamp, lastWritten: &self.lastSysWritten)
        }
        vadTimer?.resume()
    }
    
    private func stopVADPolling() {
        vadTimer?.cancel()
        vadTimer = nil
    }
    
    private var lastMicWritten: UInt64 = 0
    private var lastSysWritten: UInt64 = 0
    
    private func processVAD(for source: AudioSource, ringBuffer: AudioRingBuffer, vad: VoiceActivityDetector, prevSpeaking: inout Bool, startTimestamp: inout TimeInterval?, lastWritten: inout UInt64) {
        let currentWritten = ringBuffer.totalWritten
        var rms: Float = 0.0
        
        // Only calculate RMS if new samples arrived. SCStream stops sending samples during silence.
        if currentWritten > lastWritten {
            let samples = ringBuffer.getRecent(samplesCount: VAD.rmsWindowSamples)
            if !samples.isEmpty {
                rms = calculateRMS(samples)
            }
            lastWritten = currentWritten
        }
        
        let ts = Date().timeIntervalSince1970
        let isSpeaking = vad.process(rms: rms, timestamp: ts)

        let justEnded = !isSpeaking && prevSpeaking
        let justStarted = isSpeaking && !prevSpeaking
        prevSpeaking = isSpeaking

        let sourceName = source == .microphone ? "Mic" : "SystemAudio"

        if justStarted {
            logger.debug("Speech started on \(sourceName) (RMS: \(rms))")
            // Prefer the VAD's onsetTimestamp (first threshold crossing) over the current
            // tick time. onsetTimestamp is set when RMS first crosses speechThreshold, which
            // is up to minSpeechDuration (0.3s) earlier than the confirmation tick.
            // Using the earlier timestamp means the pre-roll covers more of the actual speech.
            startTimestamp = vad.onsetTimestamp ?? ts
        }
        if isSpeaking, let start = startTimestamp, ts - start > VAD.forceSliceAfter {
            logger.debug("Force slicing continuous speech on \(sourceName)")
            let duration = ts - start + VAD.preRollTime

            if duration > VAD.minimumDuration {
                let count = Int(duration * 16000)
                let captured = ringBuffer.getRecent(samplesCount: count)
                onSpeechDetected?(captured, source)
            }
            // Keep the last overlapTime seconds so no words are cut at the boundary.
            startTimestamp = ts - VAD.overlapTime
        } else if justEnded, let start = startTimestamp {
            logger.debug("Speech ended on \(sourceName) — capturing segment")
            startTimestamp = nil

            let duration = ts - start + VAD.preRollTime
            guard duration > VAD.minimumDuration else { return }
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
