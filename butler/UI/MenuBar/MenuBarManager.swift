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
    
    var onToggleMainWindow: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    
    // Menu Items
    private var customMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var micPermissionItem: NSMenuItem!
    private var screenPermissionItem: NSMenuItem!
    
    init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "butler")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            // Respond immediately on mouse down for a snappier feel, like standard macOS menus.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        
        setupMenu()
        setupBindings()
    }
    
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { 
            onToggleMainWindow?()
            return 
        }
        
        let isRightClick = event.type == .rightMouseUp || event.type == .rightMouseDown || event.modifierFlags.contains(.control)
        
        if isRightClick {
            customMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 5), in: sender)
        } else {
            onToggleMainWindow?()
        }
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
        
        screenPermissionItem = NSMenuItem(title: "Screen & System Audio", action: #selector(requestScreen), keyEquivalent: "")
        screenPermissionItem.target = self
        menu.addItem(screenPermissionItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Actions
        let toggleItem = NSMenuItem(title: "Toggle Session", action: #selector(toggleSession), keyEquivalent: "S")
        toggleItem.keyEquivalentModifierMask = [.shift, .option]
        toggleItem.target = self
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let analyzeItem = NSMenuItem(title: "Analyze Screen", action: #selector(analyzeScreen), keyEquivalent: "A")
        analyzeItem.keyEquivalentModifierMask = [.shift, .option]
        analyzeItem.target = self
        menu.addItem(analyzeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings & Updates & Quit
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem(title: "Quit Butler", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        self.customMenu = menu
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
    
    @objc private func analyzeScreen() {
        coordinator.triggerVisionAnalysis()
    }
    
    @objc private func toggleSession() {
        if coordinator.state == .idle {
            coordinator.startSession()
        } else {
            Task { await coordinator.stopSession() }
        }
    }
    
    @objc private func checkForUpdates() {
        onCheckForUpdates?()
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
            let panel = KeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 350),
                styleMask: [.nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            
            panel.center()
            panel.setFrameAutosaveName("ButlerSettings")
            panel.contentView = NSHostingView(rootView: SettingsView(permissionsGateway: coordinator.environment.permissionsGateway, projectContextManager: coordinator.environment.projectContextManager))
            settingsWindow = panel
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
