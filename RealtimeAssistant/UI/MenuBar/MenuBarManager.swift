import Cocoa
import SwiftUI

enum MenuBarState {
    case idle
    case listening
    case processing
}

class MenuBarManager {
    var statusItem: NSStatusItem
    
    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "RealtimeAssistant")
            button.action = #selector(menuClicked)
            button.target = self
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
    
    @objc func menuClicked() {
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func showSettings() {
        // Implement settings window display later
    }
}
