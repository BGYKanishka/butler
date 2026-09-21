import SwiftUI

struct AudioLevelView: View {
    var level: Float
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 6, height: heightForBar(at: index))
                    .animation(.spring(response: 0.15, dampingFraction: 0.6), value: level)
            }
        }
        .frame(height: 32, alignment: .center)
    }
    
    private func heightForBar(at index: Int) -> CGFloat {
        // RMS level is typically a small float (0.01 - 0.1). Multiply to make it more pronounced.
        // A multiplier of 30.0 makes normal speech more visible.
        let normalizedLevel = CGFloat(level) * 30.0
        let clampedLevel = min(max(normalizedLevel, 0), 1.0)
        
        let minHeight: CGFloat = 6.0
        if clampedLevel <= 0.02 { // Lowered noise floor threshold
            return minHeight
        }
        
        // Shape the waveform (bell curve / sine wave shape across the bars)
        let phase = Double(index) / 11.0 * .pi
        let intensity = CGFloat(sin(phase))
        
        // Add a pseudo-random modifier based on the index and current level so bars move independently
        let pseudoRandom = CGFloat(sin(Double(index) * 1.5 + Double(clampedLevel * 10)))
        let variation = 0.7 + (0.3 * pseudoRandom)
        
        let maxHeight: CGFloat = 32.0
        
        let targetHeight = minHeight + (maxHeight - minHeight) * clampedLevel * intensity * variation
        
        return max(minHeight, targetHeight)
    }
}
