import SwiftUI
import Cocoa

class ToastManager {
    static let shared = ToastManager()
    
    private var window: NSWindow?
    private var hideTimer: Timer?
    
    func showToast(text: String, duration: TimeInterval = 3.0) {
        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .stationary]
            self.window = win
        }
        
        let hostingView = NSHostingView(rootView: ToastView(text: text))
        window?.contentView = hostingView
        
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let windowWidth: CGFloat = 400
            // Position at top right
            let x = screenRect.maxX - windowWidth - 20
            let y = screenRect.maxY - 20
            window?.setFrameTopLeftPoint(NSPoint(x: x, y: y))
        }
        
        window?.orderFront(nil)
        
        hideTimer?.invalidate()
        if duration > 0 {
            hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.hideToast()
            }
        }
    }
    
    func hideToast() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window?.animator().alphaValue = 0
        }, completionHandler: {
            self.window?.orderOut(nil)
            self.window?.alphaValue = 1.0
        })
    }
}

struct ToastView: View {
    var text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Butler")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            if text.starts(with: "Answer:") {
                Text(text)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            } else {
                Text(text)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(20) // padding for shadow
    }
}
