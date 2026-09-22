import SwiftUI

struct MainWindowView: View {
    @ObservedObject var coordinator: SessionCoordinator
    @ObservedObject var permissionsGateway: PermissionsGateway

    @AppStorage(ConfigKey.isVisionEnabled) private var isVisionEnabled = false

    private var requiredPermissionsGranted: Bool {
        permissionsGateway.anyPermissionGranted
    }

    private var anyPermissionGranted: Bool {
        permissionsGateway.anyPermissionGranted
    }

    var body: some View {
        dashboardTab
            .frame(minWidth: 550, minHeight: 650)
            .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: anyPermissionGranted)
            .onChange(of: requiredPermissionsGranted) { _, granted in
                if granted && coordinator.state == .idle {
                    coordinator.startSession()
                }
            }
            .overlay(loadingOverlay)
    }
    
    private var dashboardTab: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Area - Normal size
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .padding(.top, 16)
                    
                    Text("Butler")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    
                    Text(statusText(for: coordinator.state))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(statusColor(for: coordinator.state))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor(for: coordinator.state).opacity(0.1))
                        .clipShape(Capsule())
                }
                
                // Compact Start/Stop Button
                Button(action: {
                    var isError = false
                    if case .error = coordinator.state { isError = true }
                    
                    if coordinator.state != .idle && !isError {
                        coordinator.stopSession()
                    } else {
                        coordinator.startSession()
                    }
                }) {
                    Text(buttonTitle(for: coordinator.state))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(buttonColor(for: coordinator.state))
                        .shadow(color: buttonColor(for: coordinator.state).opacity(0.4), radius: 4, x: 0, y: 2)
                )
                .disabled(!requiredPermissionsGranted)
                
                // Audio Levels
                HStack(spacing: 40) {
                    VStack {
                        Text("Microphone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        AudioLevelView(level: coordinator.micService.audioLevel)
                    }
                    
                    VStack {
                        Text("System Audio")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        AudioLevelView(level: coordinator.sysAudioService.audioLevel)
                    }
                }
                .padding(.top, 8)
                
                // Permissions
                PermissionCardView(
                    permissionsGateway: permissionsGateway,
                    micService: coordinator.micService
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 16)
                
                // AI Suggestions / Answers Area
                OverlayContentView(viewModel: coordinator.overlayViewModel)
                    .frame(minHeight: 120)
                    .padding(.horizontal, 16)
                
                // Error Banner
                if case .error(let error) = coordinator.state {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(error.localizedDescription)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding()
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.5), lineWidth: 1))
                    .padding(.horizontal, 16)
                }
                
                // Transcript View
                TranscriptView(transcripts: coordinator.transcripts)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            }
        }
    }


    @ViewBuilder
    private var loadingOverlay: some View {
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

    private func buttonTitle(for state: SessionState) -> String {
        if case .error = state { return "Start Session" }
        return state != .idle ? "Stop Session" : "Start Session"
    }

    private func buttonColor(for state: SessionState) -> Color {
        if case .error = state { return .blue }
        return state != .idle ? .red : .blue
    }
}


