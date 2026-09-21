import Foundation
import AppKit
import AVFoundation

class MicrophonePermission: ObservableObject {
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
    
    func requestPermission() {
        if isGranted {
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isGranted = granted
            }
        }
    }
}
