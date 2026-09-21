import SwiftUI

struct PermissionOnboardingView: View {
    @ObservedObject var micPermission: MicrophonePermission
    @ObservedObject var screenPermission: ScreenRecordingPermission
    
    var body: some View {
        ZStack {
            // Dark sleek background with blurred orbs
            Color.black.ignoresSafeArea()
            
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: -150, y: -150)
            
            Circle()
                .fill(Color.purple.opacity(0.3))
                .frame(width: 400, height: 400)
                .blur(radius: 120)
                .offset(x: 200, y: 150)
            
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Text("Welcome to Butler")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("We need microphone access to hear your speech,\nand screen recording access to capture system audio.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.bottom, 20)
                
                HStack(spacing: 40) {
                    permissionToggle(
                        title: "Microphone",
                        icon: "mic.fill",
                        isGranted: micPermission.isGranted,
                        action: { micPermission.requestPermission() }
                    )
                    
                    permissionToggle(
                        title: "System Audio",
                        icon: "macwindow",
                        isGranted: screenPermission.isGranted,
                        action: { screenPermission.requestPermission() }
                    )
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).clipShape(RoundedRectangle(cornerRadius: 24)))
            )
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    @ViewBuilder
    private func permissionToggle(title: String, icon: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            if !isGranted { action() }
        }) {
            VStack(spacing: 12) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 24))
                    .foregroundColor(isGranted ? .green : .white)
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(isGranted ? "Granted" : "Grant Access")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(isGranted ? .green.opacity(0.8) : .gray)
            }
            .frame(width: 120, height: 100)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isGranted ? Color.green.opacity(0.1) : Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isGranted ? Color.green.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(), value: isGranted)
    }
}
