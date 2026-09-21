import Cocoa
import SwiftUI

enum MenuBarState {
    case idle
    case listening
    case processing
}

class MenuBarManager {
    var statusItem: NSStatusItem
    private var settingsWindow: NSWindow?
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "butler")
        }
        
        setupMenu()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
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
