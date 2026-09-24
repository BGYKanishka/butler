import Foundation
import AppKit
import AVFoundation

@MainActor
class MicrophonePermission: BasePermissionTracker {
    
    override init() {
        super.init()
        checkPermission()
        startObserving()
    }
    
    override func performCheck() {
        checkPermission()
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isGranted = true
        case .notDetermined:
            // Don't auto-request, let user initiate
            isGranted = false
        case .denied, .restricted:
            isGranted = false
        @unknown default:
            isGranted = false
        }
    }
    
    func requestPermission() async -> Bool {
        if isGranted {
            return true
        }
        
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .denied || status == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
            return false
        }
        
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        self.isGranted = granted
        return granted
    }
}
