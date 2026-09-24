import Foundation
import os

class AudioRingBuffer {
    private var buffer: [Float]
    private var head: Int = 0
    private var count: Int = 0
    private let capacity: Int
    private var lock = os_unfair_lock_s() // Real-time safe lock
    
    private(set) var totalWritten: UInt64 = 0
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0.0, count: capacity)
    }
    
    func push(_ samples: [Float], timestamp: UInt64) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let samplesCount = samples.count
        guard samplesCount > 0 else { return }
        
        let writeCount = min(samplesCount, capacity)
        let startIndex = samplesCount - writeCount
        
        buffer.withUnsafeMutableBufferPointer { dest in
            samples.withUnsafeBufferPointer { src in
                guard let destBase = dest.baseAddress, let srcBase = src.baseAddress else { return }
                
                let spaceAtEnd = capacity - head
                if writeCount <= spaceAtEnd {
                    memcpy(destBase + head, srcBase + startIndex, writeCount * MemoryLayout<Float>.stride)
                } else {
                    memcpy(destBase + head, srcBase + startIndex, spaceAtEnd * MemoryLayout<Float>.stride)
                    let remaining = writeCount - spaceAtEnd
                    memcpy(destBase, srcBase + startIndex + spaceAtEnd, remaining * MemoryLayout<Float>.stride)
                }
            }
        }
        
        head = (head + writeCount) % capacity
        count = min(capacity, count + writeCount)
        totalWritten += UInt64(writeCount)
    }
    
    func getRecent(samplesCount: Int) -> [Float] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let countToRead = min(samplesCount, count)
        if countToRead == 0 { return [] }
        
        var result = [Float](repeating: 0.0, count: countToRead)
        
        let readIndex = (head - countToRead + capacity) % capacity
        
        result.withUnsafeMutableBufferPointer { dest in
            buffer.withUnsafeBufferPointer { src in
                guard let destBase = dest.baseAddress, let srcBase = src.baseAddress else { return }
                
                let spaceAtEnd = capacity - readIndex
                if countToRead <= spaceAtEnd {
                    memcpy(destBase, srcBase + readIndex, countToRead * MemoryLayout<Float>.stride)
                } else {
                    memcpy(destBase, srcBase + readIndex, spaceAtEnd * MemoryLayout<Float>.stride)
                    let remaining = countToRead - spaceAtEnd
                    memcpy(destBase + spaceAtEnd, srcBase, remaining * MemoryLayout<Float>.stride)
                }
            }
        }
        
        return result
    }
}
