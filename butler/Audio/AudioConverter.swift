import Foundation
import AVFoundation
import os

private let logger = Logger(subsystem: "com.butler", category: "Audio")

class AudioConverter {
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat
    
    init(from sourceFormat: AVAudioFormat? = nil) throws {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16000,
                                         channels: 1,
                                         interleaved: false) else {
            throw AssistantError.initializationFailed("Failed to create target audio format")
        }
        self.targetFormat = format
        
        if let sourceFormat = sourceFormat {
            setupConverter(from: sourceFormat)
        }
    }
    
    func setupConverter(from format: AVAudioFormat) {
        if sourceFormat == format && converter != nil { return }
        logger.debug("Setting up AVAudioConverter \(format.sampleRate)Hz → \(self.targetFormat.sampleRate)Hz")
        self.sourceFormat = format
        self.converter = AVAudioConverter(from: format, to: targetFormat)
    }
    
    func convert(buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if sourceFormat == nil || sourceFormat != buffer.format {
            setupConverter(from: buffer.format)
        }
        
        guard let converter = converter else { return nil }
        
        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }
        
        var error: NSError?
        var provided = false
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error || error != nil {
            logger.error("Audio conversion failed: \(error?.localizedDescription ?? "unknown error")")
            return nil
        }
        
        return outputBuffer
    }
}
