import Foundation
import AppKit
import ScreenCaptureKit

@MainActor
class ScreenRecordingPermission: BasePermissionTracker {
    @Published var pollingGaveUp: Bool = false
    
    override init() {
        super.init()
        checkPermission()
        startObserving()
    }
    
    override func performCheck() {
        checkPermission()
    }
    
    /// Checks screen recording permission silently. Uses CGPreflight and optionally falls back to SCShareableContent.
    func checkPermission(allowFallback: Bool = false) {
        if isGranted { return }
        
        if CGPreflightScreenCaptureAccess() {
            isGranted = true
        } else if allowFallback {
            // Fall back to SCShareableContent because of Xcode's ad-hoc code signing
            verifySilentlyWithSCShareableContent()
        }
    }
    
    /// Async fallback using SCShareableContent. Only called during polling as it can trigger system dialogs.
    private func verifySilentlyWithSCShareableContent() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            Task { @MainActor in
                if error == nil && content != nil {
                    self?.isGranted = true
                }
            }
        }
    }
    
    /// Called on "Grant Access" tap. Shows dialog once, then opens Settings and polls.
    func requestPermission() {
        if isGranted { return }
        pollingGaveUp = false
        
        // Shows the system prompt once per app launch. Subsequent calls are no-ops.
        let alreadyGranted = CGRequestScreenCaptureAccess()
        if alreadyGranted {
            isGranted = true
            return
        }
        
        // The user needs to toggle in System Settings manually.
        openSettingsAndPoll()
    }
    
    private func openSettingsAndPoll() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        pollPermission(attempts: 60)
    }
    
    /// Polls using silent checks to avoid re-triggering the dialog.
    private func pollPermission(attempts: Int) {
        guard attempts > 0 && !isGranted else {
            if !isGranted { self.pollingGaveUp = true }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.checkPermission(allowFallback: true)
                
                // Wait briefly for async SCShareableContent before continuing polling.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    Task { @MainActor in
                        if self.isGranted == false {
                            self.pollPermission(attempts: attempts - 1)
                        }
                    }
                }
            }
        }
    }
}

