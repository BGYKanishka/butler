import SwiftUI

struct MainWindowView: View {
    @StateObject private var micService = MicrophoneCaptureService()
    @StateObject private var sysAudioService = SystemAudioCaptureService()
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
                        AudioLevelView(level: micService.audioLevel)
                            .frame(width: 100)
                    }
                    
                    VStack {
                        Text("System Audio")
                        AudioLevelView(level: sysAudioService.audioLevel)
                            .frame(width: 100)
                    }
                }
                .padding()
                
                HStack {
                    Button(micService.isRunning ? "Stop Session" : "Start Session") {
                        if micService.isRunning {
                            micService.stop()
                            sysAudioService.stop()
                        } else {
                            Task {
                                try? await micService.start()
                                try? await sysAudioService.start()
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
