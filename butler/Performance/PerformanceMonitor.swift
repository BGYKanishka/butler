import Foundation
import os

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let logger = OSLog(subsystem: "com.example.butler", category: "Performance")
    private var marks: [String: OSSignpostID] = [:]
    
    private init() {}
    
    func start(_ task: String) {
        let signpostID = OSSignpostID(log: logger)
        marks[task] = signpostID
        os_signpost(.begin, log: logger, name: "PerformanceTask", signpostID: signpostID, "Started task: %{public}s", task)
    }
    
    func end(_ task: String) {
        guard let signpostID = marks[task] else {
            os_log("Task %{public}s ended without being started.", log: logger, type: .info, task)
            return
        }
        
        os_signpost(.end, log: logger, name: "PerformanceTask", signpostID: signpostID, "Ended task: %{public}s", task)
        marks.removeValue(forKey: task)
    }
    
}
