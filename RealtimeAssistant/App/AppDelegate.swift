import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var overlayPanel: OverlayPanel?
    var menuBarManager: MenuBarManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager()
        
        let overlayView = OverlayContentView()
        overlayPanel = OverlayPanel(contentView: overlayView)
        overlayPanel?.makeKeyAndOrderFront(nil)
    }
}
