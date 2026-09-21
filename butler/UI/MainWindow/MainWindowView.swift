import SwiftUI

struct MainWindowView: View {
    @ObservedObject var coordinator: SessionCoordinator
    @StateObject private var micPermission = MicrophonePermission()
    @StateObject private var screenPermission = ScreenRecordingPermission()
    
    var body: some View {
        Group {
            if !micPermission.isGranted || !screenPermission.isGranted {
                PermissionOnboardingView(micPermission: micPermission, screenPermission: screenPermission)
            } else {
                VStack(spacing: 20) {
                    Text("butler Session Control")
                        .font(.headline)
                    
                    HStack(spacing: 30) {
                        VStack {
                            Text("Microphone")
                            AudioLevelView(level: coordinator.micService.audioLevel)
                                .frame(width: 100)
                        }
                        
                        VStack {
                            Text("System Audio")
                            AudioLevelView(level: coordinator.sysAudioService.audioLevel)
                                .frame(width: 100)
                        }
                    }
                    .padding()
                    
                    PerformanceView(coordinator: coordinator)
                    
                    TranscriptView(transcripts: coordinator.transcripts)
                    
                    HStack(spacing: 16) {
                        // Visual State Indicator
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor(for: coordinator.state))
                                .frame(width: 10, height: 10)
                                .shadow(color: statusColor(for: coordinator.state).opacity(0.6), radius: 4, x: 0, y: 0)
                            
                            Text(statusText(for: coordinator.state))
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                        
                        Spacer()
                        
                        Button(action: {
                            if coordinator.state != .idle {
                                coordinator.stopSession()
                            } else {
                                coordinator.startSession()
                            }
                        }) {
                            Text(coordinator.state != .idle ? "Stop Session" : "Start Session")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(coordinator.state != .idle ? .red : .blue)
                        .controlSize(.large)
                    }
                }
                .padding()
                .frame(minWidth: 400, minHeight: 300)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .overlay(
            Group {
                if coordinator.isLoadingModels {
                    ZStack {
                        Color.black.opacity(0.6).ignoresSafeArea()
                        
                        VStack(spacing: 24) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            VStack(spacing: 8) {
                                Text("Waking up AI engines...")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text("Loading Llama model into Metal unified memory.\nThis may take a few seconds.")
                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(40)
                        .background(
                            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                                .cornerRadius(24)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
                    }
                    .transition(.opacity)
                }
            }
        )
        .animation(.easeInOut, value: coordinator.isLoadingModels)
    }
    
    private func statusColor(for state: SessionState) -> Color {
        switch state {
        case .idle: return .gray
        case .listening: return .green
        case .processing: return .orange
        case .answering: return .blue
        case .error: return .red
        }
    }
    
    private func statusText(for state: SessionState) -> String {
        switch state {
        case .idle: return "Idle"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .answering: return "Answering..."
        case .error: return "Error"
        }
    }
}
