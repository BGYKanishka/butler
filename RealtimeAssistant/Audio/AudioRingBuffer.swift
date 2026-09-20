import Foundation

class AudioRingBuffer {
    private var buffer: [Float]
    private var head: Int = 0
    private var tail: Int = 0
    private let capacity: Int
    private let lock = NSLock() // A simple lock for now. In a strictly real-time C++ audio engine, we'd use atomics.
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0.0, count: capacity)
    }
    
    func push(_ samples: [Float], timestamp: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        
        for sample in samples {
            buffer[head] = sample
            head = (head + 1) % capacity
            if head == tail {
                // Buffer full, advance tail to overwrite oldest data
                tail = (tail + 1) % capacity
            }
        }
    }
    
    func getRecent(samplesCount: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        let countToRead = min(samplesCount, availableItems())
        if countToRead == 0 { return [] }
        
        var result = [Float](repeating: 0.0, count: countToRead)
        
        // We read backwards from head
        var readIndex = (head - countToRead + capacity) % capacity
        
        for i in 0..<countToRead {
            result[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        
        return result
    }
    
    private func availableItems() -> Int {
        if head >= tail {
            return head - tail
        } else {
            return capacity - tail + head
        }
    }
}
