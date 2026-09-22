import SwiftUI

struct PermissionOnboardingView: View {
    @ObservedObject var permissionsGateway: PermissionsGateway
    @ObservedObject var micService: MicrophoneCaptureService
    
    @State private var phase = 0.0
    
    var body: some View {
        ZStack {
            // Futuristic Dark Background
            Color(white: 0.05).ignoresSafeArea()
            
            // Animated Glowing Orbs
            Circle()
                .fill(
                    RadialGradient(gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.clear]), center: .center, startRadius: 10, endRadius: 250)
                )
                .frame(width: 500, height: 500)
                .offset(x: cos(phase) * 100, y: sin(phase) * 100)
                .blur(radius: 60)
            
            Circle()
                .fill(
                    RadialGradient(gradient: Gradient(colors: [Color.purple.opacity(0.5), Color.clear]), center: .center, startRadius: 10, endRadius: 200)
                )
                .frame(width: 400, height: 400)
                .offset(x: -cos(phase) * 150, y: -sin(phase) * 80)
                .blur(radius: 50)
            
            VStack(spacing: 30) {
                VStack(spacing: 12) {
                    Text("Welcome to Butler")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: Color.blue.opacity(0.5), radius: 10, x: 0, y: 0)
                    
                    Text("To empower your AI meeting assistant, please grant the following permissions. (Note: System Audio captures all audio from your display, including other apps).")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .frame(maxWidth: 350)
                }
                .padding(.bottom, 20)
                
                HStack(spacing: 30) {
                    permissionToggle(
                        title: "Microphone",
                        icon: "mic.fill",
                        isGranted: permissionsGateway.isMicGranted,
                    action: { requestMic() }
                    )
                    
                    permissionToggle(
                        title: "System Audio",
                        icon: "macwindow.on.rectangle",
                        isGranted: permissionsGateway.isScreenGranted,
                        pollingGaveUp: permissionsGateway.screenPermission.pollingGaveUp,
                        action: { permissionsGateway.requestScreenPermission() },
                        checkAgainAction: { permissionsGateway.screenPermission.checkPermission(allowFallback: true) }
                    )
                }
                
                if permissionsGateway.anyPermissionGranted {
                    if permissionsGateway.isMicGranted {
                        VStack(spacing: 8) {
                            Text("Microphone Input")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.gray)
                            
                            Text("Microphone Ready")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.green)
                                .padding(.top, 4)
                        }
                        .padding(.top, 20)
                        .transition(.opacity)
                    }
                    
                    Button(action: {
                        NotificationCenter.default.post(name: NSNotification.Name("SkipOnboarding"), object: nil)
                    }) {
                        Text("Continue & Start")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 160, height: 44)
                            .background(Color.blue)
                            .cornerRadius(22)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                    .transition(.opacity)
                }
            }
            .padding(50)
            .background(
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0.0)]), startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 20)
        }
        .frame(minWidth: 600, minHeight: 450)
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }
    
    @ViewBuilder
    private func permissionToggle(
        title: String, 
        icon: String, 
        isGranted: Bool, 
        pollingGaveUp: Bool = false, 
        action: @escaping () -> Void, 
        checkAgainAction: (() -> Void)? = nil
    ) -> some View {
        Button(action: {
            if !isGranted {
                if pollingGaveUp {
                    checkAgainAction?()
                } else {
                    action()
                }
            }
        }) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.white.opacity(0.05))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isGranted ? .green : .white)
                }
                .overlay(
                    Circle()
                        .stroke(isGranted ? Color.green.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                )
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(isGranted ? "Granted" : (pollingGaveUp ? "Check Again" : "Grant Access"))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(isGranted ? .green.opacity(0.9) : (pollingGaveUp ? .orange : .gray))
                }
            }
            .frame(width: 140, height: 160)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isGranted ? Color.green.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isGranted)
    }

    private func requestMic() {
        Task { @MainActor in
            await permissionsGateway.requestMicPermission()
        }
    }
}
