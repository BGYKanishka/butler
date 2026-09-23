import AVFoundation

let engine = AVAudioEngine()
let inputNode = engine.inputNode
let inputFormat = inputNode.outputFormat(forBus: 0)
print("Input format: \(inputFormat)")
