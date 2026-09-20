import Foundation
import ScreenCaptureKit

class ScreenRecordingPermission: ObservableObject {
    @Published var isGranted: Bool = false
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        if #available(macOS 14.0, *) {
            isGranted = CGPreflightScreenCaptureAccess()
        } else {
            // Fallback for older macOS versions
            isGranted = CGPreflightScreenCaptureAccess()
        }
    }
    
    func requestPermission() {
        if #available(macOS 14.0, *) {
            CGRequestScreenCaptureAccess()
        } else {
            CGRequestScreenCaptureAccess()
        }
        // Poll for changes since there is no callback in older APIs, but modern SCK provides streams which will just fail if denied.
        // We will just re-check.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkPermission()
        }
    }
}
