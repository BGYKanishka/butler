import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            if !viewModel.subtitles.isEmpty {
                VStack(spacing: 8) {
                    ForEach(viewModel.subtitles, id: \.self) { subtitle in
                        Text(subtitle)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
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
                }
            }
            
            if let response = viewModel.llmResponse {
                Text(response)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
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
            
            Spacer()
        }
        .padding()
        .animation(.easeInOut, value: viewModel.subtitles)
        .animation(.spring(), value: viewModel.llmResponse)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
