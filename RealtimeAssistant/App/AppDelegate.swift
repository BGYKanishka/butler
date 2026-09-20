import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow!
    var overlayPanel: OverlayPanel!
    var menuBarManager: MenuBarManager!
    let coordinator = MainCoordinator()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let contentView = MainWindowView(coordinator: self.coordinator)
        
        mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        mainWindow.center()
        mainWindow.setFrameAutosaveName("Main Window")
        mainWindow.contentView = NSHostingView(rootView: contentView)
        mainWindow.makeKeyAndOrderFront(nil)
        
        let overlayContentView = OverlayContentView(viewModel: self.coordinator.overlayViewModel)
        overlayPanel = OverlayPanel(contentView: overlayContentView)
        overlayPanel.orderFront(nil)
        
        menuBarManager = MenuBarManager()
    }
}
