import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let question = viewModel.detectedQuestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DETECTED QUESTION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                        .tracking(1.0)
                    Text(question)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .cornerRadius(12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if let response = viewModel.llmResponse {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BUTLER'S ANSWER")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.blue.opacity(0.8))
                        .tracking(1.0)
                    Text(response)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                }
                .padding(16)
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .cornerRadius(16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            viewModel.statusText == "Answering" ? Color.blue.opacity(0.6) : Color.white.opacity(0.15),
                            lineWidth: viewModel.statusText == "Answering" ? 2.0 : 1.0
                        )
                )
                .shadow(
                    color: viewModel.statusText == "Answering" ? Color.blue.opacity(0.4) : Color.black.opacity(0.3),
                    radius: viewModel.statusText == "Answering" ? 15 : 10,
                    x: 0, y: 5
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Status Footer
            HStack(spacing: 8) {
                if let latency = viewModel.latency {
                    Text(String(format: "Latency: %.1fs", latency))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("•")
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                Circle()
                    .fill(viewModel.statusText == "Listening" ? Color.green : (viewModel.statusText == "Answering" ? Color.blue : Color.orange))
                    .frame(width: 6, height: 6)
                    .shadow(color: viewModel.statusText == "Listening" ? Color.green : (viewModel.statusText == "Answering" ? Color.blue : Color.orange), radius: 3)
                
                Text(viewModel.statusText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(viewModel.statusText == "Listening" ? .green : (viewModel.statusText == "Answering" ? .blue : .orange))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(Capsule()))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
            
            if viewModel.detectedQuestion == nil && !viewModel.subtitles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.subtitles.suffix(3)) { item in
                        Text(item.text)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
            
            Spacer()
        }
        .padding()
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.detectedQuestion)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: viewModel.llmResponse)
        .animation(.easeInOut(duration: 0.2), value: viewModel.statusText)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
