import Cocoa
import SwiftUI
import Combine
import HotKey

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    var sessionCoordinator = SessionCoordinator()
    
    private var cancellables = Set<AnyCancellable>()
    private var toggleSessionHotKey: HotKey?
    private var stopSessionHotKey: HotKey?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager(coordinator: sessionCoordinator)
        
        setupBindings()
        setupHotKeys()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Explicitly stop the session and unload ML engines before exit().
        // This ensures llama_free / whisper_free are called while the Metal
        // device is still alive, draining residency sets and preventing the
        // GGML_ASSERT([rsets->data count] == 0) crash in ggml_metal_device_free.
        if sessionCoordinator.state != .idle {
            sessionCoordinator.stopSession()
        }
        sessionCoordinator.llmEngine.unload()
        sessionCoordinator.whisperEngine.unload()
    }
    
    private func setupBindings() {
        sessionCoordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { @MainActor [weak self] state in
                switch state {
                case .idle:
                    self?.menuBarManager?.setState(.idle)
                case .listening:
                    self?.menuBarManager?.setState(.listening)
                case .processing:
                    self?.menuBarManager?.setState(.processing)
                case .answering:
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
        
        // Option + Command + S: Stop Session
        stopSessionHotKey = HotKey(key: .s, modifiers: [.option, .command])
        stopSessionHotKey?.keyDownHandler = { [weak self] in
            self?.sessionCoordinator.stopSession()
        }
    }
}
