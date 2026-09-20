import XCTest
@testable import butler

final class butlerTests: XCTestCase {
    
    func testAudioRingBuffer() throws {
        let buffer = AudioRingBuffer(capacity: 100)
        
        let samples: [Float] = [0.1, 0.2, 0.3]
        buffer.push(samples)
        
        let recent = buffer.readRecent(count: 3)
        XCTAssertEqual(recent, samples)
    }
    
    func testVoiceActivityDetector() throws {
        let vad = VoiceActivityDetector()
        
        // Silence
        XCTAssertFalse(vad.process(rms: 0.001, timestamp: 0.0))
        XCTAssertFalse(vad.process(rms: 0.001, timestamp: 0.1))
        
        // Speech (threshold > 0.02, minDuration = 0.2)
        XCTAssertFalse(vad.process(rms: 0.1, timestamp: 0.2)) // Start speaking
        XCTAssertTrue(vad.process(rms: 0.1, timestamp: 0.45)) // Duration 0.25 > 0.2
        
        // Silence again (threshold < 0.01, maxSilence = 0.6)
        XCTAssertTrue(vad.process(rms: 0.001, timestamp: 0.5)) // Start silence
        XCTAssertFalse(vad.process(rms: 0.001, timestamp: 1.2)) // Duration 0.7 > 0.6
    }
    
    func testQuestionDetector() throws {
        let detector = QuestionDetector()
        
        XCTAssertEqual(detector.detect(transcript: "Hello world.", source: .system), .none)
        XCTAssertEqual(detector.detect(transcript: "What is the meaning of life?", source: .system), .strongQuestion)
        XCTAssertEqual(detector.detect(transcript: "I heard what happened.", source: .system), .possibleQuestion)
        XCTAssertEqual(detector.detect(transcript: "What is the meaning of life?", source: .microphone), .none)
    }
}
