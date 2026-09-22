import XCTest
@testable import butler

final class butlerTests: XCTestCase {
    
    func testAudioRingBuffer() throws {
        let buffer = AudioRingBuffer(capacity: 100)
        
        let samples: [Float] = [0.1, 0.2, 0.3]
        buffer.push(samples, timestamp: 0)
        
        let recent = buffer.getRecent(samplesCount: 3)
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
    
    func testContextManager() async throws {
        let manager = ContextManager()
        
        let turn1 = ConversationTurn(id: UUID(), source: .system, type: .statement, text: "Hello there.", timestamp: Date().addingTimeInterval(-100))
        let turn2 = ConversationTurn(id: UUID(), source: .microphone, type: .statement, text: "Hi, how are you?", timestamp: Date().addingTimeInterval(-50))
        let turn3 = ConversationTurn(id: UUID(), source: .system, type: .statement, text: "I'm doing well, thank you.", timestamp: Date())
        
        await manager.addTurn(turn1)
        await manager.addTurn(turn2)
        await manager.addTurn(turn3)
        
        let contextString = await manager.getRecentContext()
        XCTAssertFalse(contextString.contains("Hello there.")) // Evicted because it's older than 60s
        XCTAssertTrue(contextString.contains("[LOCAL]: Hi, how are you?"))
        XCTAssertTrue(contextString.contains("[REMOTE]: I'm doing well, thank you."))
    }
}
