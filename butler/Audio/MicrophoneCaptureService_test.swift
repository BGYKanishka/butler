import AVFoundation

func fixMaxFrames(node: AVAudioNode) {
    node.auAudioUnit.maximumFramesToRender = 4096
}
