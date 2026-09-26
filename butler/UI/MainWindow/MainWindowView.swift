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
            .frame(width: 550, height: 650)
            .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: anyPermissionGranted)
            .onChange(of: requiredPermissionsGranted) { _, granted in
                if granted && coordinator.state == .idle {
                    coordinator.startSession()
                }
            }
            .overlay(loadingOverlay)
    }
    
    private var dashboardTab: some View {
        VStack(spacing: 0) {
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
                .overlay(Rectangle().stroke(Color.red.opacity(0.5), lineWidth: 1))
            }
            
            // Header with Start/Stop
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("Butler")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    var isError = false
                    if case .error = coordinator.state { isError = true }
                    if coordinator.state != .idle && !isError {
                        Task { await coordinator.stopSession() }
                    } else {
                        coordinator.startSession()
                    }
                }) {
                    Text(buttonTitle(for: coordinator.state))
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(buttonColor(for: coordinator.state))
                )
                
                Button(action: {
                    coordinator.triggerVisionAnalysis()
                }) {
                    Image(systemName: "viewfinder")
                    Text("Analyze Screen")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isVisionDisabled(state: coordinator.state, loading: coordinator.isLoadingModels) ? Color.gray : Color.purple)
                )
                .foregroundColor(.white)
                .disabled(isVisionDisabled(state: coordinator.state, loading: coordinator.isLoadingModels))
                
                Button(action: {
                    coordinator.onShowSettings?()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
                
                Button(action: {
                    coordinator.onHideMainWindow?()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Audio Levels
            HStack(spacing: 40) {
                VStack {
                    Text("Microphone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AudioLevelView(level: coordinator.micAudioLevel)
                }
                
                VStack {
                    Text("System Audio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    AudioLevelView(level: coordinator.sysAudioLevel)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            // Transcript View taking up the full remaining space
            TranscriptView(transcripts: coordinator.transcripts)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
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
    
    private func isVisionDisabled(state: SessionState, loading: Bool) -> Bool {
        if loading { return true }
        if case .idle = state { return true }
        if case .error = state { return true }
        return false
    }
}


