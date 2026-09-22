import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    // Status colors
    private var statusColor: Color {
        switch viewModel.statusText {
        case "Listening": return .green
        case "Processing": return .orange
        case "Answering": return .blue
        default: return .gray
        }
    }
    
    // Check if we are in an expanded answering state
    private var isExpanded: Bool {
        viewModel.detectedQuestion != nil || viewModel.llmResponse != nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                // Expanded Question & Answer Card
                VStack(alignment: .leading, spacing: 16) {
                    if let question = viewModel.detectedQuestion {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DETECTED QUESTION")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(1.0)
                            Text(question)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    }
                    
                    if let response = viewModel.llmResponse {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("BUTLER")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.blue.opacity(0.8))
                                .tracking(1.0)
                            Text(response)
                                .font(.system(size: 18, weight: .regular, design: .rounded))
                                .foregroundColor(.white)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 10)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            } else {
                // Subtitles preview when not expanded
                if !viewModel.subtitles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.subtitles.suffix(2)) { item in
                            Text(item.text)
                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            
            // Compact Status Pill
            HStack(spacing: 8) {
                // Animated glowing dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.8), radius: 4)
                
                Text(viewModel.statusText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(statusColor)
                
                if let latency = viewModel.latency, isExpanded {
                    Text("•")
                        .foregroundColor(.gray.opacity(0.5))
                        .padding(.horizontal, 2)
                    Text(String(format: "%.1fs", latency))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .frame(maxWidth: .infinity, alignment: isExpanded ? .leading : .center)
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.subtitles)
        .animation(.easeInOut(duration: 0.2), value: viewModel.statusText)
        .colorScheme(.dark) // Force dark mode
        .frame(maxWidth: 400, alignment: .bottomLeading)
    }
}
