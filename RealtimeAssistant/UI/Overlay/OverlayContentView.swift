import SwiftUI

struct OverlayContentView: View {
    @ObservedObject var viewModel = OverlayViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = viewModel.currentQuestion {
                Text("Q: \(question)")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            if let answer = viewModel.currentAnswer {
                Text("A: \(answer)")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Spacer()
            
            HStack {
                Text("Latency: \(String(format: "%.1f", viewModel.latency))s | \(viewModel.status)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
    }
}

class OverlayViewModel: ObservableObject {
    @Published var currentQuestion: String? = "Ready to assist"
    @Published var currentAnswer: String? = "..."
    @Published var latency: Double = 0.0
    @Published var status: String = "Idle"
}
