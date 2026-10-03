import Foundation

class VoiceActivityDetector {
    var speechThreshold: Float = 0.01
    var silenceThreshold: Float = 0.005
    var minSpeechDuration: TimeInterval = 0.3
    var maxSilenceInSpeech: TimeInterval = 1.0

    var onsetResetGrace: TimeInterval = 0.15

    private var isSpeaking: Bool = false
    private var silenceStartTime: TimeInterval?
    private var speechStartTime: TimeInterval?

    private(set) var onsetTimestamp: TimeInterval?

    
    private var dipStartTime: TimeInterval?

    func process(rms: Float, timestamp: TimeInterval) -> Bool {
        if rms > speechThreshold {
            // Above speech threshold — clear any active dip timer and extend the onset window.
            dipStartTime = nil
            silenceStartTime = nil

            if !isSpeaking {
                if speechStartTime == nil {
                    speechStartTime = timestamp
                    onsetTimestamp  = timestamp   // record the FIRST crossing for pre-roll math
                }
                if timestamp - (speechStartTime ?? timestamp) >= minSpeechDuration {
                    isSpeaking = true
                }
            }
        } else if rms < silenceThreshold {
            if isSpeaking {
                // Already confirmed speaking — use the normal silence-end timer.
                if silenceStartTime == nil {
                    silenceStartTime = timestamp
                }
                if timestamp - (silenceStartTime ?? timestamp) >= maxSilenceInSpeech {
                    isSpeaking = false
                    silenceStartTime = nil
                    onsetTimestamp = nil
                }
            } else {
                // Not yet confirmed speaking — apply grace period before resetting onset clock.
                // This prevents a brief soft consonant from restarting the 0.3s requirement.
                if speechStartTime != nil {
                    if dipStartTime == nil {
                        dipStartTime = timestamp
                    }
                    if timestamp - (dipStartTime ?? timestamp) >= onsetResetGrace {
                        // Sustained dip beyond grace — genuinely not speech yet.
                        speechStartTime = nil
                        onsetTimestamp  = nil
                        dipStartTime    = nil
                    }
                }
            }
        }
        // RMS in the dead band [silenceThreshold, speechThreshold] — no state change.
        return isSpeaking
    }

    func reset() {
        isSpeaking = false
        silenceStartTime = nil
        speechStartTime  = nil
        onsetTimestamp   = nil
        dipStartTime     = nil
    }
}
