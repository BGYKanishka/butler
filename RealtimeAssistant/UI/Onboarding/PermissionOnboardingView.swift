import SwiftUI

struct PermissionOnboardingView: View {
    @StateObject private var micPermission = MicrophonePermission()
    @StateObject private var screenPermission = ScreenRecordingPermission()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to RealtimeAssistant")
                .font(.largeTitle)
            
            Text("We need microphone access to hear your speech, and screen recording access to capture system audio.")
                .multilineTextAlignment(.center)
                .padding()
            
            HStack(spacing: 40) {
                VStack {
                    if micPermission.isGranted {
                        Text("Microphone: Granted")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Mic") {
                            micPermission.requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                VStack {
                    if screenPermission.isGranted {
                        Text("Screen: Granted")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Screen") {
                            screenPermission.requestPermission()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}
