import SwiftUI

struct AudioLevelView: View {
    var level: Float
    
    // Smooth the level for animations
    @State private var animatedLevel: CGFloat = 0.0
    
    var body: some View {
        ZStack {
            // Background container
            Capsule()
                .fill(Color.black.opacity(0.1))
                .frame(width: 80, height: 32)
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            
            // Glowing pulsing orbs
            HStack(spacing: -10) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .scaleEffect(1.0 + (animatedLevel * 0.5))
                    .blur(radius: 4)
                    .blendMode(.screen)
                
                Circle()
                    .fill(Color.purple)
                    .frame(width: 20, height: 20)
                    .scaleEffect(1.0 + (animatedLevel * 0.8))
                    .blur(radius: 4)
                    .blendMode(.screen)
                
                Circle()
                    .fill(Color.pink)
                    .frame(width: 20, height: 20)
                    .scaleEffect(1.0 + (animatedLevel * 0.6))
                    .blur(radius: 4)
                    .blendMode(.screen)
            }
        }
        .onChange(of: level) { _, newValue in
            // Normalize level (RMS usually small)
            let normalized = min(max(CGFloat(newValue) * 30.0, 0), 1.0)
            withAnimation(.spring(response: 0.15, dampingFraction: 0.6)) {
                animatedLevel = normalized
            }
        }
    }
}
