import Foundation
import AppKit

@MainActor
class BasePermissionTracker: ObservableObject {
    @Published var isGranted: Bool = false
    private var observer: Any?
    
    init() {}
    
    func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.performCheck()
            }
        }
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func performCheck() {
        // To be overridden in subclasses
    }
}
