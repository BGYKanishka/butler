import Cocoa
import SwiftUI
import Combine
import HotKey
import Sparkle

class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var sessionCoordinator = SessionCoordinator(environment: AppEnvironment())
    
    private var cancellables = Set<AnyCancellable>()
    private var toggleSessionHotKey: HotKey?
    private var analyzeScreenHotKey: HotKey?
    private var toggleWindowHotKey: HotKey?
    
    var mainWindow: NSPanel?
    var settingsWindow: NSWindow?

    private var updaterController: SPUStandardUpdaterController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Hide from dock
        
        sessionCoordinator.onHideMainWindow = { [weak self] in
            self?.mainWindow?.orderOut(nil)
        }
        sessionCoordinator.onShowMainWindow = { [weak self] in
            self?.mainWindow?.makeKeyAndOrderFront(nil)
        }
        sessionCoordinator.onShowSettings = { [weak self] in
            self?.showSettings()
        }
        
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

        setupMainWindow()
        setupBindings()
        setupHotKeys()
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // We don't need to manually wait for whisper or llama models to unload.
        // The OS instantly reclaims all memory on process exit. Waiting for background 
        // queues to clear just makes the app feel unresponsive when quitting.
        return .terminateNow
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            toggleMainWindow()
        }
        return true
    }
    
    private func setupMainWindow() {
        let view = MainWindowView(
            coordinator: sessionCoordinator,
            permissionsGateway: sessionCoordinator.environment.permissionsGateway,
            projectContextManager: sessionCoordinator.environment.projectContextManager
        )
        let hostingView = NSHostingView(rootView: view)
        
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 650),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        let isPinned = UserDefaults.standard.bool(forKey: "isWindowPinned")
        panel.isFloatingPanel = isPinned
        panel.level = isPinned ? .floating : .normal
        panel.collectionBehavior = isPinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none // Hides from screen sharing!
        panel.isReleasedWhenClosed = false
        
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        panel.contentView = hostingView
        
        // Position at top center
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - (550 / 2)
            // Just below the notch/menu bar
            let y = screen.frame.maxY - 650 - 20 // 20 pt padding from top
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        
        self.mainWindow = panel
        panel.makeKeyAndOrderFront(nil)
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("ToggleWindowPin"), object: nil, queue: .main) { [weak panel] _ in
            let pinned = UserDefaults.standard.bool(forKey: "isWindowPinned")
            panel?.isFloatingPanel = pinned
            panel?.level = pinned ? .floating : .normal
            panel?.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
            panel?.orderFront(nil)
        }
    }
    
    @objc func toggleMainWindow() {
        guard let panel = mainWindow else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // Re-center on active screen
            if let screen = NSScreen.main {
                let x = screen.visibleFrame.midX - (panel.frame.width / 2)
                let y = screen.frame.maxY - panel.frame.height - 20
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
    
    @objc func showSettings() {
        if settingsWindow == nil {
            let panel = KeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: 350, height: 550),
                styleMask: [.nonactivatingPanel, .fullSizeContentView],
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
            panel.sharingType = .none
            panel.isReleasedWhenClosed = false
            
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            
            panel.center()
            panel.setFrameAutosaveName("ButlerSettings")
            panel.contentView = NSHostingView(rootView: SettingsView(permissionsGateway: sessionCoordinator.environment.permissionsGateway, projectContextManager: sessionCoordinator.environment.projectContextManager))
            settingsWindow = panel
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func setupBindings() {
        // No bindings needed here right now
    }
    
    private func setupHotKeys() {
        // Shift + Option + S: Toggle Session
        toggleSessionHotKey = HotKey(key: .s, modifiers: [.shift, .option])
        toggleSessionHotKey?.keyDownHandler = { [weak self] in
            guard let self = self else { return }
            if self.sessionCoordinator.state == .idle {
                self.sessionCoordinator.startSession()
            } else {
                Task { await self.sessionCoordinator.stopSession() }
            }
        }
        
        // Shift + Option + A: Analyze Screen
        analyzeScreenHotKey = HotKey(key: .a, modifiers: [.shift, .option])
        analyzeScreenHotKey?.keyDownHandler = { [weak self] in
            self?.sessionCoordinator.triggerVisionAnalysis()
        }
        
        // Shift + Option + W: Toggle Main Window
        toggleWindowHotKey = HotKey(key: .w, modifiers: [.shift, .option])
        toggleWindowHotKey?.keyDownHandler = { [weak self] in
            self?.toggleMainWindow()
        }
    }
    
    // MARK: - Sparkle Gentle Reminders
    
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        return true
    }
}
