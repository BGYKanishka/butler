import AVFoundation

class MicrophonePermission: ObservableObject {
    @Published var isGranted: Bool = false
    
    init() {
        checkStatus()
    }
    
    func checkStatus() {
        isGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isGranted = granted
            }
        }
    }
}
