import Cocoa
import SwiftUI
import Combine
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayPanel: OverlayPanel?
    var menuBarManager: MenuBarManager?
    var sessionCoordinator = SessionCoordinator()
    
    private var cancellables = Set<AnyCancellable>()
    private var toggleSessionHotKey: HotKey?
    private var toggleOverlayHotKey: HotKey?
    private var stopSessionHotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
        
        let overlayView = OverlayContentView(viewModel: sessionCoordinator.overlayViewModel)
        overlayPanel = OverlayPanel(contentView: overlayView)
        // Hidden by default, toggled via hotkey
        // overlayPanel?.makeKeyAndOrderFront(nil)
        
        setupBindings()
        setupHotKeys()
    }
    
    private func setupBindings() {
        sessionCoordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .idle:
                    self?.menuBarManager?.setState(.idle)
                case .listening:
                    self?.menuBarManager?.setState(.listening)
                case .processing, .answering:
                    self?.menuBarManager?.setState(.processing)
                case .error:
                    self?.menuBarManager?.setState(.idle)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupHotKeys() {
        // Option + Command + Space: Toggle Session
        toggleSessionHotKey = HotKey(key: .space, modifiers: [.option, .command])
        toggleSessionHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            if self.sessionCoordinator.state == .idle {
                self.sessionCoordinator.startSession()
            } else {
                self.sessionCoordinator.stopSession()
            }
        }
        
        // Option + Command + A: Toggle Overlay
        toggleOverlayHotKey = HotKey(key: .a, modifiers: [.option, .command])
        toggleOverlayHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            if self.overlayPanel?.isVisible == true {
                self.overlayPanel?.orderOut(nil)
            } else {
                self.overlayPanel?.makeKeyAndOrderFront(nil)
            }
        }
        
        // Option + Command + S: Stop Session
        stopSessionHotKey = HotKey(key: .s, modifiers: [.option, .command])
        stopSessionHotKey?.keyDownHandler = { [weak self] in
            self?.sessionCoordinator.stopSession()
        }
    }
}
