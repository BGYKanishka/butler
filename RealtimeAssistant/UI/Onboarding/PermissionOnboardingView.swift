import SwiftUI

struct PermissionOnboardingView: View {
    @StateObject private var micPermission = MicrophonePermission()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to RealtimeAssistant")
                .font(.largeTitle)
            
            Text("We need microphone access to hear your speech.")
                .multilineTextAlignment(.center)
            
            if micPermission.isGranted {
                Text("Microphone access granted!")
                    .foregroundColor(.green)
            } else {
                Button("Grant Microphone Permission") {
                    micPermission.requestPermission()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}
