import Cocoa
import SwiftUI
import Combine

enum MenuBarState {
    case idle
    case listening
    case processing
}

@MainActor
class MenuBarManager {
    var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    
    private var coordinator: SessionCoordinator
    private var cancellables = Set<AnyCancellable>()
    
    // Menu Items
    private var statusMenuItem: NSMenuItem!
    private var micPermissionItem: NSMenuItem!
    private var screenPermissionItem: NSMenuItem!
    
    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "butler")
        }
        
        setupMenu()
        setupBindings()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Status Item
        statusMenuItem = NSMenuItem(title: "Butler: Idle", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false // Just a label
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Permissions
        let permsHeader = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        permsHeader.isEnabled = false
        menu.addItem(permsHeader)
        
        micPermissionItem = NSMenuItem(title: "Microphone", action: #selector(requestMic), keyEquivalent: "")
        micPermissionItem.target = self
        menu.addItem(micPermissionItem)
        
        screenPermissionItem = NSMenuItem(title: "System Audio", action: #selector(requestScreen), keyEquivalent: "")
        screenPermissionItem.target = self
        menu.addItem(screenPermissionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings & Quit
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem(title: "Quit Butler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    private func setupBindings() {
        let permissions = coordinator.environment.permissionsGateway
        
        permissions.$isMicGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                self?.micPermissionItem.state = granted ? .on : .off
            }
            .store(in: &cancellables)
            
        permissions.$isScreenGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] granted in
                self?.screenPermissionItem.state = granted ? .on : .off
            }
            .store(in: &cancellables)
            
        coordinator.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateStatusText(state)
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusText(_ state: SessionState) {
        switch state {
        case .idle:
            statusMenuItem.title = "Butler: Idle"
        case .listening:
            statusMenuItem.title = "Butler: Listening..."
        case .processing:
            statusMenuItem.title = "Butler: Processing..."
        case .answering:
            statusMenuItem.title = "Butler: Answering..."
        case .error(let err):
            statusMenuItem.title = "Butler: Error (\(err.localizedDescription))"
        }
    }
    
    @objc private func requestMic() {
        Task {
            await coordinator.environment.permissionsGateway.requestMicPermission()
        }
    }
    
    @objc private func requestScreen() {
        coordinator.environment.permissionsGateway.requestScreenPermission()
    }
    
    func setState(_ state: MenuBarState) {
        switch state {
        case .idle:
            statusItem.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Idle")
        case .listening:
            statusItem.button?.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "Listening")
        case .processing:
            statusItem.button?.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Processing")
        }
    }
    
    @objc func showSettings() {
        if settingsWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 350),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false)
            win.center()
            win.setFrameAutosaveName("ButlerSettings")
            win.title = "Butler Settings"
            win.contentView = NSHostingView(rootView: SettingsView())
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
