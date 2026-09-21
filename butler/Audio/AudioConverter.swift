import Foundation
import AVFoundation

class AudioConverter {
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat
    
    init() throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16000,
                                         channels: 1,
                                         interleaved: false) else {
            throw AssistantError.initializationFailed("Failed to create target audio format")
        }
        self.targetFormat = format
    }
    
    func setupConverter(from format: AVAudioFormat) {
        if sourceFormat == format { return }
        self.sourceFormat = format
        self.converter = AVAudioConverter(from: format, to: targetFormat)
    }
    
    func convert(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let format = sourceFormat else {
            setupConverter(from: buffer.format)
            guard sourceFormat != nil else { return nil }
            return convert(buffer: buffer)
        }
        
        guard let converter = converter else { return nil }
        
        let capacity = AVAudioFrameCount(ceil(converter.outputFormat.sampleRate / converter.inputFormat.sampleRate * Double(buffer.frameLength)))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error || error != nil {
            print("Audio conversion error: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        return outputBuffer
    }
}
