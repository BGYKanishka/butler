import Foundation
import os.signpost

class SignpostLogger {
    static let shared = SignpostLogger()
    let log: OSLog
    
    private init() {
        self.log = OSLog(subsystem: "com.example.butler", category: "Performance")
    }
    
    func begin(name: StaticString) -> OSSignpostID {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: signpostID)
        return signpostID
    }
    
    func end(name: StaticString, signpostID: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: signpostID)
    }
}
