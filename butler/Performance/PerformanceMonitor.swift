import Foundation
import os

class PerformanceMonitor {
    static let shared = PerformanceMonitor()
    
    private let logger = Logger(subsystem: "com.example.butler", category: "Performance")
    private var marks: [String: CFAbsoluteTime] = [:]
    
    private init() {}
    
    func start(_ task: String) {
        marks[task] = CFAbsoluteTimeGetCurrent()
        logger.debug("Started task: \(task)")
    }
    
    func end(_ task: String) {
        guard let startTime = marks[task] else {
            logger.warning("Task \(task) ended without being started.")
            return
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        marks.removeValue(forKey: task)
        
        logger.info("Task \(task) completed in \(String(format: "%.3f", duration)) seconds.")
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
            logger.info("Memory usage: \(String(format: "%.2f", memoryMB)) MB")
        } else {
            logger.error("Failed to get memory usage.")
        }
    }
}
