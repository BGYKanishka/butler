import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let question = viewModel.detectedQuestion {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REMOTE:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.gray)
                    Text(question)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .cornerRadius(12)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if let response = viewModel.llmResponse {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ANSWER:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.blue.opacity(0.8))
                    Text(response)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding()
                .background(
                    VisualEffectView(material: .menu, blendingMode: .behindWindow)
                        .cornerRadius(16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Status Footer
            HStack {
                if let latency = viewModel.latency {
                    Text(String(format: "Latency: %.1fs", latency))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                    Text("|")
                        .foregroundColor(.gray.opacity(0.5))
                }
                Text(viewModel.statusText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(viewModel.statusText == "Listening" ? .green : .orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
        .animation(.spring(), value: viewModel.detectedQuestion)
        .animation(.spring(), value: viewModel.llmResponse)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
