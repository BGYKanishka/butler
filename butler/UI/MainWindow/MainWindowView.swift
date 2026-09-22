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
        ScrollView {
            VStack(spacing: 16) {
                // ── Header ──────────────────────────────────────────────
                HStack {
                    Text("butler Session Control")
                        .font(.headline)
                    Spacer()
                    Toggle("Enable Vision", isOn: $isVisionEnabled)
                        .toggleStyle(.switch)
                }

                // ── Inline Permission Card ──
                PermissionCardView(
                    permissionsGateway: permissionsGateway,
                    micService: coordinator.micService
                )
                .transition(.move(edge: .top).combined(with: .opacity))


                // ── Suggestions area ────────────────────────────────────
                OverlayContentView(viewModel: coordinator.overlayViewModel)
                    .frame(minHeight: 150)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(16)

                // ── Error banner ────────────────────────────────────────
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
                }

                // ── Audio level meters ──────────────────────────────────
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

                // ── Status + Stop/Start ─────────────────────────────────
                HStack(spacing: 16) {
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
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(buttonColor(for: coordinator.state))
                    .controlSize(.large)
                    .disabled(!requiredPermissionsGranted)
                }
                
                #if DEBUG
                // ── Test Tools ──────────────────────────────────────────
                Button(action: {
                    coordinator.testWithAudioFile(path: "/Users/yehankanishka/Project/meeting_assistant/system_test_ track.m4a", forceAnswer: true)
                }) {
                    Text("Test Audio Track")
                        .font(.system(.body, design: .rounded))
                }
                .padding(.top, 8)
                #endif
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: anyPermissionGranted)
        // Auto-start once required permissions become available
        .onChange(of: requiredPermissionsGranted) { _, granted in
            if granted && coordinator.state == .idle {
                coordinator.startSession()
            }
        }
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

    private func buttonTitle(for state: SessionState) -> String {
        if case .error = state { return "Start Session" }
        return state != .idle ? "Stop Session" : "Start Session"
    }

    private func buttonColor(for state: SessionState) -> Color {
        if case .error = state { return .blue }
        return state != .idle ? .red : .blue
    }
}

