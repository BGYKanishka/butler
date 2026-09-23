import Foundation

class VoiceActivityDetector {
    var speechThreshold: Float = 0.025
    var silenceThreshold: Float = 0.015
    var minSpeechDuration: TimeInterval = 0.5
    var maxSilenceInSpeech: TimeInterval = 1.0
    
    private var isSpeaking: Bool = false
    private var silenceStartTime: TimeInterval?
    private var speechStartTime: TimeInterval?
    
    func process(rms: Float, timestamp: TimeInterval) -> Bool {
        if rms > speechThreshold {
            silenceStartTime = nil
            if !isSpeaking {
                if speechStartTime == nil {
                    speechStartTime = timestamp
                }
                if timestamp - (speechStartTime ?? timestamp) >= minSpeechDuration {
                    isSpeaking = true
                }
            }
        } else if rms < silenceThreshold {
            speechStartTime = nil
            if isSpeaking {
                if silenceStartTime == nil {
                    silenceStartTime = timestamp
                }
                if timestamp - (silenceStartTime ?? timestamp) >= maxSilenceInSpeech {
                    isSpeaking = false
                    silenceStartTime = nil
                }
            }
        }
        return isSpeaking
    }
}
