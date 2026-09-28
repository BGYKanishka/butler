import Foundation
import AppKit
import ScreenCaptureKit

@MainActor
class ScreenRecordingPermission: BasePermissionTracker {
    @Published var isRequestInProgress: Bool = false

    private var pollTask: Task<Void, Never>?

    override init() {
        super.init()
        silentCheck()
        startObserving()
    }

    override func performCheck() {
        silentCheck()
    }

    override func performCheckAsync() async {
        // Background check uses ONLY CGPreflight — never SCShareableContent.
        // SCShareableContent CAN trigger the system permission prompt and must
        // only be called during user-initiated polling (after "Request Access" tap).
        silentCheck()
    }

    deinit {
        pollTask?.cancel()
    }

    // MARK: - Silent Checks

    /// Fast preflight check. Works with proper code signing.
    func silentCheck() {
        // Always re-check — permission can be revoked from System Settings at any time
        if CGPreflightScreenCaptureAccess() {
            isGranted = true
            stopPolling()
        } else {
            // Only reset to false if we previously thought it was granted.
            // This handles revocation from System Settings.
            if isGranted {
                isGranted = false
            }
        }
    }

    /// Fallback check via SCShareableContent. Used ONLY during explicit polling
    /// (after the user taps "Request Access") to detect grants on Xcode ad-hoc builds.
    /// WARNING: On the very first call or after revocation, this MAY show the system
    /// prompt — which is intentional during polling, but must never be called passively.
    private func silentCheckWithFallback() async {
        // Primary: instant CGPreflight check
        if CGPreflightScreenCaptureAccess() {
            isGranted = true
            stopPolling()
            return
        }

        // Fallback: SCShareableContent query (safe — reflects actual granted/denied state silently).
        await withCheckedContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
                Task { @MainActor [weak self] in
                    guard let self else { continuation.resume(); return }
                    if error == nil, content != nil {
                        self.isGranted = true
                        self.stopPolling()
                    } else {
                        // Permission is denied or revoked — reflect that in the UI
                        self.isGranted = false
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - User-Initiated Request

    func requestPermission() {
        guard !isGranted else { return }

        // Cancel any existing poll so this is a clean restart
        stopPolling()

        // Show the native macOS dialog. After the very first show, macOS suppresses
        // subsequent calls and returns false (permission not yet granted via Settings).
        if CGRequestScreenCaptureAccess() {
            isGranted = true
            return
        }

        // Always open System Settings to the Screen Recording pane so the user
        // can grant access via the toggle (required after first denial).
        openSystemSettings()

        // Start polling to detect when the user flips the toggle.
        startPolling()
    }

    /// Cancels an in-progress request. Used by the UI "Cancel" button.
    func cancelRequest() {
        stopPolling()
    }

    // MARK: - System Settings

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        isRequestInProgress = true

        pollTask = Task { [weak self] in
            guard let self else { return }
            // Poll for up to 2 minutes (80 × 1.5 s). The user can cancel early.
            for _ in 0..<80 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await self.silentCheckWithFallback()
                if self.isGranted { return }
            }
            // Timed out — let the user try again.
            if !Task.isCancelled {
                self.isRequestInProgress = false
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        isRequestInProgress = false
    }
}
