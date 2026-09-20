import AppKit

class ScreenRecordingPermission: ObservableObject {
    @Published var isGranted: Bool = false
    
    init() {
        checkStatus()
    }
    
    func checkStatus() {
        isGranted = CGPreflightScreenCaptureAccess()
    }
    
    func requestPermission() {
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkStatus()
        }
    }
}
