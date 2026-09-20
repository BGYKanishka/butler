import Foundation
import AVFoundation

class AudioConverter {
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    
    init() {
        self.outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    }
    
    func convert(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let inputFormat = buffer.format as AVAudioFormat? else { return nil }
        
        if converter == nil || converter?.inputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }
        
        guard let converter = converter else { return nil }
        
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        let status = converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error || error != nil {
            return nil
        }
        return convertedBuffer
    }
}
