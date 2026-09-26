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
            
        coordinator.visionAnswerPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] answer in
                self?.showTemporaryTitle(answer)
            }
            .store(in: &cancellables)
    }
    
    private func showTemporaryTitle(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanText.isEmpty {
            if let range = cleanText.range(of: #"(?<=\[Answer:)[^\]]+"#, options: .regularExpression) {
                // Extracted the MCQ answer successfully!
                let answer = cleanText[range].trimmingCharacters(in: .whitespaces)
                ToastManager.shared.showToast(text: "Answer: \(answer)", duration: 5.0)
            } else if cleanText.starts(with: "[Answer:") {
                // It's currently typing out the answer tag
                ToastManager.shared.showToast(text: "Thinking...", duration: 5.0)
            }
            // If it doesn't start with [Answer:, it's not an MCQ, so we show nothing in the Toast.
        }
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
            coordinator.stopSession()
        }
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
