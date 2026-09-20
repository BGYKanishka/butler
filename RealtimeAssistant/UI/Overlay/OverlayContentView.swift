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
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                            .transition(.opacity)
                    }
                }
            }
            
            if let response = viewModel.llmResponse {
                Text(response)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.yellow)
                    .padding()
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(16)
                    .shadow(color: .blue.opacity(0.6), radius: 6, x: 0, y: 3)
                    .transition(.slide)
            }
            
            Spacer()
        }
        .padding()
        .animation(.easeInOut, value: viewModel.subtitles)
        .animation(.spring(), value: viewModel.llmResponse)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
