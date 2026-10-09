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
        isGranted = CGPreflightScreenCaptureAccess()
    }

    override func performCheckAsync() async {
        isGranted = CGPreflightScreenCaptureAccess()
    }

    private func checkPermissionAsync() async {
        // CGPreflightScreenCaptureAccess doesn't trigger the OS prompt.
        isGranted = CGPreflightScreenCaptureAccess()
    }

    // Actively probe SCShareableContent ONLY during polling
    // to bypass the Xcode ad-hoc signing bug.
    private func checkPermissionActively() async {
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

        // CGRequestScreenCaptureAccess() will trigger the native OS prompt if not yet determined.
        let _ = CGRequestScreenCaptureAccess()

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
                await self.checkPermissionActively()

                if !self.isGranted && self.isRequestInProgress {
                    self.pollPermission(attempts: attempts - 1)
                } else {
                    self.isRequestInProgress = false
                }
            }
        }
    }
}
