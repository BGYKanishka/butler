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
                await self?.performCheckAsync()
            }
        }
    }
    
    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    /// Sync check — override for quick, non-async checks.
    func performCheck() {}
    
    /// Async check — override for checks that need async APIs (e.g. SCShareableContent).
    /// Default falls back to the sync version.
    func performCheckAsync() async {
        performCheck()
    }
}
