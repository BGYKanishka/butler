import SwiftUI

struct MainWindowView: View {
    @StateObject private var micService = MicrophoneCaptureService()
    @StateObject private var micPermission = MicrophonePermission()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("RealtimeAssistant Session Control")
                .font(.headline)
            
            if !micPermission.isGranted {
                PermissionOnboardingView()
            } else {
                AudioLevelView(level: micService.audioLevel)
                    .frame(width: 200)
                    .padding()
                
                HStack {
                    Button(micService.isRunning ? "Stop Session" : "Start Session") {
                        if micService.isRunning {
                            micService.stop()
                        } else {
                            Task {
                                try? await micService.start()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(micService.isRunning ? .red : .blue)
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}
