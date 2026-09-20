import Cocoa
import SwiftUI

class OverlayPanel: NSPanel {
    init(contentView: some View) {
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .resizable, .fullSizeContentView, .titled, .closable]
        
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 400, height: 200),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.sharingType = .none
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = true
        
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        
        visualEffect.addSubview(hostingView)
        hostingView.frame = visualEffect.bounds
        
        self.contentView = visualEffect
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
    }
    
    override var canBecomeKey: Bool {
        return false
    }
    
    override var canBecomeMain: Bool {
        return false
    }
}
