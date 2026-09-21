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
    
    func logMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0,
                          &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let memoryMB = Double(info.resident_size) / 1048576.0
            os_log("Memory usage: %.2f MB", log: logger, type: .info, memoryMB)
        } else {
            os_log("Failed to get memory usage.", log: logger, type: .error)
        }
    }
}
