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
    
    func checkPermission() {
        if #available(macOS 14.0, *) {
            isGranted = CGPreflightScreenCaptureAccess()
        } else {
            // Fallback for older macOS versions
            isGranted = CGPreflightScreenCaptureAccess()
        }
    }
    
    func requestPermission() {
        if isGranted {
            return
        }
        if #available(macOS 14.0, *) {
            CGRequestScreenCaptureAccess()
        } else {
            CGRequestScreenCaptureAccess()
        }
        
        pollPermission(attempts: 60)
    }
    
    private func pollPermission(attempts: Int) {
        guard attempts > 0 && !isGranted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermission()
            if self?.isGranted == false {
                self?.pollPermission(attempts: attempts - 1)
            }
        }
    }
}
