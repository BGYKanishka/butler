import SwiftUI

@main
struct butlerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainWindowView(coordinator: appDelegate.sessionCoordinator)
        }
    }
}
