import Foundation
import os

class MemoryMonitor {
    static let shared = MemoryMonitor()
    private let logger = OSLog(subsystem: "com.example.butler", category: "Memory")
    private let budgetLimitInBytes: UInt64 = 15 * 1024 * 1024 * 1024 // 15 GB
    
    private var timer: Timer?
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkMemory()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func checkMemory() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_,
                          task_flavor_t(MACH_TASK_BASIC_INFO),
                          $0,
                          &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedBytes = info.resident_size
            let usedGB = Double(usedBytes) / 1024.0 / 1024.0 / 1024.0
            
            os_log("Current memory usage: %.2f GB", log: logger, type: .debug, usedGB)
            
            if usedBytes > budgetLimitInBytes {
                os_log("MEMORY WARNING: Usage exceeded 15 GB budget! (%.2f GB)", log: logger, type: .fault, usedGB)
            }
        }
    }
}
