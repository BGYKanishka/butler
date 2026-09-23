import AVFoundation

let engine = AVAudioEngine()
let inputNode = engine.inputNode
do {
    try inputNode.setVoiceProcessingEnabled(true)
    print("Voice processing enabled")
} catch {
    print("Failed to enable: \(error)")
}
let inputFormat = inputNode.outputFormat(forBus: 0)
print("Input format: \(inputFormat)")
