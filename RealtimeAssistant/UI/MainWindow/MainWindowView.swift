import SwiftUI

struct MainWindowView: View {
    @ObservedObject var coordinator: SessionCoordinator
    @StateObject private var micPermission = MicrophonePermission()
    @StateObject private var screenPermission = ScreenRecordingPermission()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("RealtimeAssistant Session Control")
                .font(.headline)
            
            if !micPermission.isGranted || !screenPermission.isGranted {
                PermissionOnboardingView()
            } else {
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
                
                HStack {
                    Button(coordinator.state != .idle ? "Stop Session" : "Start Session") {
                        if coordinator.state != .idle {
                            coordinator.stopSession()
                        } else {
                            coordinator.startSession()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(coordinator.state != .idle ? .red : .blue)
                    
                    Button("Simulate Question") {
                        coordinator.simulateSpeechDetected(text: "What would you do if the server crashes?", source: .system)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}
