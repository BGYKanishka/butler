import Foundation
import AppKit
import ScreenCaptureKit

class ScreenRecordingPermission: ObservableObject {
    @Published var isGranted: Bool = false
    private var observer: Any?
    
    init() {
        checkPermission()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkPermission()
        }
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Checks screen recording permission silently.
    /// Uses CGPreflightScreenCaptureAccess() which is synchronous and never shows a dialog.
    func checkPermission() {
        if isGranted { return }
        
        if CGPreflightScreenCaptureAccess() {
            isGranted = true
        }
        // Do NOT fall back to SCShareableContent automatically here.
        // Because of Xcode's ad-hoc code signing (CODE_SIGN_IDENTITY: "-"),
        // every build creates a new signature. If we call SCShareableContent
        // automatically, macOS will treat it as a new app and show the
        // permission dialog on every single launch!
    }
    
    /// Async fallback check using SCShareableContent.
    /// This CAN trigger a dialog on some macOS versions if permission isn't granted,
    /// so we only call it during polling (after the user has explicitly tapped Grant).
    private func verifySilentlyWithSCShareableContent() {
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                if error == nil && content != nil {
                    self?.isGranted = true
                }
            }
        }
    }
    
    /// Called when the user explicitly taps "Grant Access" in the permission card.
    /// Shows the system dialog once, then opens System Settings and polls.
    func requestPermission() {
        if isGranted { return }
        
        // CGRequestScreenCaptureAccess() shows the system prompt once per app launch.
        // Subsequent calls are no-ops that return false immediately.
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
    
    /// Polls using only CGPreflight (silent) + SCShareableContent fallback.
    /// No CGRequestScreenCaptureAccess() — that would re-trigger the dialog.
    private func pollPermission(attempts: Int) {
        guard attempts > 0 && !isGranted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            self.checkPermission()
            
            // If CGPreflight failed, try SCShareableContent as fallback
            if !self.isGranted {
                self.verifySilentlyWithSCShareableContent()
            }
            
            // checkPermission is partially async (SCShareableContent), so wait
            // a beat before checking if we need to continue polling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isGranted == false {
                    self.pollPermission(attempts: attempts - 1)
                }
            }
        }
    }
}

