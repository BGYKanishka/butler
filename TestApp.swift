import Cocoa
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var settingsWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.center()
        
        let btn = NSButton(title: "Settings", target: self, action: #selector(showSettings))
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        btn.frame = NSRect(x: 100, y: 100, width: 100, height: 30)
        view.addSubview(btn)
        
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false)
            settingsWindow?.center()
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
            settingsWindow?.contentView = view
            settingsWindow?.isReleasedWhenClosed = false
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("Settings shown")
    }
}
