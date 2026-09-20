import SwiftUI

struct PerformanceView: View {
    @ObservedObject var coordinator: SessionCoordinator
    
    // Placeholder metrics until Branch 9 completes full PerformanceMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance Metrics")
                .font(.headline)
            
            HStack {
                MetricCard(title: "Status", value: "\(coordinator.state)")
                MetricCard(title: "Mic VAD", value: coordinator.micService.audioLevel > 0.05 ? "Speech" : "Silence")
                MetricCard(title: "Sys VAD", value: coordinator.sysAudioService.audioLevel > 0.05 ? "Speech" : "Silence")
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .bold()
        }
        .frame(minWidth: 80, alignment: .leading)
        .padding(8)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }
}
