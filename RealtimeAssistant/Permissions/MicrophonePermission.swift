import Foundation
import AVFoundation

class MicrophonePermission: ObservableObject {
    @Published var isGranted: Bool = false
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isGranted = true
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            isGranted = false
        @unknown default:
            isGranted = false
        }
    }
    
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isGranted = granted
            }
        }
    }
}
