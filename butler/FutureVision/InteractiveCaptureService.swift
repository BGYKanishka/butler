import Foundation
import AppKit

public class InteractiveCaptureService {
    
    public static let shared = InteractiveCaptureService()
    
    private init() {}
    
    /// Triggers the native macOS interactive screen capture.
    /// - Parameter completion: Called with the URL of the saved image if successful, or nil if cancelled.
    public func captureRegion(completion: @escaping (URL?) -> Void) {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFileUrl = tempDirectory.appendingPathComponent("butler_vision_capture_\(UUID().uuidString).png")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        // -i : Interactive mode (crosshairs to select area)
        // -x : Mute the camera shutter sound
        task.arguments = ["-i", "-x", tempFileUrl.path]
        
        task.terminationHandler = { process in
            if process.terminationStatus == 0 {
                // Success - execute completion on main thread as UI might update
                DispatchQueue.main.async {
                    completion(tempFileUrl)
                }
            } else {
                // Cancelled or failed
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
        
        do {
            try task.run()
        } catch {
            print("Failed to launch screencapture: \(error)")
            DispatchQueue.main.async {
                completion(nil)
            }
        }
    }
}
