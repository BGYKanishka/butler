import AVFoundation
import CoreAudio
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
    
    private var isStarting = false
    
    func start() async throws {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // Apply the user's preferred microphone if one has been saved.
        let savedID = UserDefaults.standard.string(forKey: ConfigKey.selectedMicrophoneID) ?? ""
        if !savedID.isEmpty {
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone, .external],
                mediaType: .audio,
                position: .unspecified
            ).devices
            if let preferred = devices.first(where: { $0.uniqueID == savedID }) {
                // AVAudioEngine respects the system default input; route via AVCaptureDevice.
                // On macOS we set the preferred device via CoreAudio device ID.
                var deviceID = AudioDeviceID(0)
                var propSize = UInt32(MemoryLayout<AudioDeviceID>.size)
                var addr = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyDefaultInputDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                // Translate UID → AudioDeviceID then set it as the default input.
                var uid = preferred.uniqueID as CFString
                var uidPropAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                withUnsafePointer(to: &uid) { ptr in
                    let rawPtr = UnsafeRawPointer(ptr)
                    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &uidPropAddr, UInt32(MemoryLayout<CFString>.size), rawPtr, &propSize, &deviceID)
                }
                if deviceID != 0 {
                    AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID)
                }
            }
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AssistantError.initializationFailed("Invalid microphone format (channels: \(inputFormat.channelCount), sampleRate: \(inputFormat.sampleRate)). Please check your Bluetooth connection.")
        }

        self.converter = try AudioConverter(from: nil)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
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
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        await MainActor.run {
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
