import Foundation
import os

class AudioRingBuffer {
    private var buffer: [Float]
    private let capacity: Int
    private var writeIndex: Int = 0
    private var lock = os_unfair_lock_s()
    
    init(capacity: Int = 320_000) { // 20 seconds at 16kHz
        self.capacity = capacity
        self.buffer = Array(repeating: 0.0, count: capacity)
    }
    
    func push(_ samples: [Float]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
    }
    
    func readRecent(count: Int) -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let readCount = min(count, capacity)
        var result = [Float](repeating: 0.0, count: readCount)
        
        var readIdx = (writeIndex - readCount + capacity) % capacity
        for i in 0..<readCount {
            result[i] = buffer[readIdx]
            readIdx = (readIdx + 1) % capacity
        }
        return result
    }
}
