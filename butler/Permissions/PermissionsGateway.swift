import Foundation
import AppKit
import Combine

@MainActor
class PermissionsGateway: ObservableObject {
    @Published var isMicGranted: Bool = false
    @Published var isScreenGranted: Bool = false
    
    let micPermission: MicrophonePermission
    let screenPermission: ScreenRecordingPermission
    private var cancellables = Set<AnyCancellable>()
    
    init(micPermission: MicrophonePermission = MicrophonePermission(),
         screenPermission: ScreenRecordingPermission = ScreenRecordingPermission()) {
        self.micPermission = micPermission
        self.screenPermission = screenPermission
        
        // Forward published properties
        micPermission.$isGranted
            .receive(on: DispatchQueue.main)
            .assign(to: &$isMicGranted)
            
        screenPermission.$isGranted
            .receive(on: DispatchQueue.main)
            .assign(to: &$isScreenGranted)
    }
    
    var allPermissionsGranted: Bool {
        isMicGranted && isScreenGranted
    }
    
    var anyPermissionGranted: Bool {
        isMicGranted || isScreenGranted
    }
    
    @discardableResult
    func requestMicPermission() async -> Bool {
        return await micPermission.requestPermission()
    }
    
    func requestScreenPermission() {
        screenPermission.requestPermission()
    }
}
