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
    
    @MainActor
    init(micPermission: MicrophonePermission? = nil,
         screenPermission: ScreenRecordingPermission? = nil) {
        let mic = micPermission ?? MicrophonePermission()
        let screen = screenPermission ?? ScreenRecordingPermission()
        
        self.micPermission = mic
        self.screenPermission = screen
        
        // Forward published properties
        self.micPermission.$isGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                self?.isMicGranted = granted
            }
            .store(in: &cancellables)
            
        self.screenPermission.$isGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                self?.isScreenGranted = granted
            }
            .store(in: &cancellables)
        
        // Bubble up isRequestInProgress so any SwiftUI views on PermissionsGateway re-render
        self.screenPermission.$isRequestInProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
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
