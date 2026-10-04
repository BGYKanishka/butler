import Foundation
import AppKit
import ScreenCaptureKit

@MainActor
class ScreenRecordingPermission: BasePermissionTracker {
    @Published var isRequestInProgress: Bool = false

    override init() {
        super.init()
        // Use async check immediately — CGPreflightScreenCaptureAccess() is
        // unreliable under Xcode ad-hoc signing (always returns false).
        Task { await checkPermissionAsync() }
        startObserving()
    }

    override func performCheck() {
        Task { await checkPermissionAsync() }
    }

    override func performCheckAsync() async {
        await checkPermissionAsync()
    }

    // Probe SCShareableContent directly — the same approach used in
    // SystemAudioCaptureService — as the actual source of truth.
    // A successful call means the user has granted screen recording access.
    private func checkPermissionAsync() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            isGranted = true
            isRequestInProgress = false
        } catch {
            isGranted = false
        }
    }

    func requestPermission() {
        guard !isGranted else { return }

        isRequestInProgress = true

        // If permission was previously denied, CGRequestScreenCaptureAccess()
        // silently does nothing. Open System Settings directly so the user
        // knows where to flip the toggle — same pattern as MicrophonePermission.
        let alreadyDenied = !CGPreflightScreenCaptureAccess()
        if alreadyDenied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else {
            CGRequestScreenCaptureAccess()
        }

        pollPermission(attempts: 60)
    }

    func cancelRequest() {
        isRequestInProgress = false
    }

    private func pollPermission(attempts: Int) {
        guard attempts > 0, !isGranted, isRequestInProgress else {
            isRequestInProgress = false
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                await self.checkPermissionAsync()

                if !self.isGranted && self.isRequestInProgress {
                    self.pollPermission(attempts: attempts - 1)
                } else {
                    self.isRequestInProgress = false
                }
            }
        }
    }
}
