import SwiftUI

/// A compact inline permission card embedded in the main window.
/// Shown only when one or more permissions are not yet granted.
struct PermissionCardView: View {
    @ObservedObject var permissionsGateway: PermissionsGateway
    @ObservedObject var micService: MicrophoneCaptureService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.orange)
                Text("Permissions Required")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("Grant at least one to start")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                permissionButton(
                    title: "Microphone",
                    icon: "mic.fill",
                    isGranted: permissionsGateway.isMicGranted,
                    action: {
                        _ = Task { @MainActor in
                            await permissionsGateway.requestMicPermission()
                        }
                    }
                )

                permissionButton(
                    title: "System Audio",
                    icon: "macwindow.on.rectangle",
                    isGranted: permissionsGateway.isScreenGranted,
                    action: { permissionsGateway.requestScreenPermission() }
                )
            }

            if permissionsGateway.isMicGranted {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                        .font(.caption)
                    AudioLevelView(level: micService.audioLevel)
                        .frame(maxWidth: .infinity)
                }
                .onAppear { _ = Task { try? await micService.start() } }
                .transition(.opacity)
            }
        }
        .padding(14)
        .frame(maxWidth: 400) // Prevent stretching on wide windows
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: permissionsGateway.isMicGranted)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: permissionsGateway.isScreenGranted)
    }

    @ViewBuilder
    private func permissionButton(
        title: String,
        icon: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { if !isGranted { action() } }) {
            HStack(spacing: 8) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .foregroundColor(isGranted ? .green : .secondary)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(isGranted ? "Granted" : "Tap to grant")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(isGranted ? .green : .secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isGranted ? Color.green.opacity(0.1) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isGranted ? Color.green.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isGranted)
    }
}
