import XCTest
@testable import Butler

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
        vad.speechThreshold = 0.02
        vad.silenceThreshold = 0.01
        vad.minSpeechDuration = 0.2
        vad.maxSilenceInSpeech = 0.6
        
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
    

    func testContextManager() async throws {
        let manager = ContextManager()
        
        let turn1 = ConversationTurn(id: UUID(), source: .system, type: .statement, text: "Hello there.", timestamp: Date().addingTimeInterval(-700))
        let turn2 = ConversationTurn(id: UUID(), source: .microphone, type: .statement, text: "Hi, how are you?", timestamp: Date().addingTimeInterval(-50))
        let turn3 = ConversationTurn(id: UUID(), source: .system, type: .statement, text: "I'm doing well, thank you.", timestamp: Date())
        
        await manager.addTurn(turn1)
        await manager.addTurn(turn2)
        await manager.addTurn(turn3)
        
        let contextString = await manager.getRecentContext()
        XCTAssertFalse(contextString.contains("Hello there.")) // Evicted because it's older than 600s
        XCTAssertTrue(contextString.contains("[CANDIDATE (USER)]: Hi, how are you?"))
        XCTAssertTrue(contextString.contains("[INTERVIEWER]: I'm doing well, thank you."))
    }

    func testContextManagerUnansweredQueryWhenNoQuery() async throws {
        let manager = ContextManager()
        
        // Assistant answered a previous vision request
        let imageTurn = ConversationTurn(id: UUID(), source: .microphone, type: .question, text: "[Image Analyzed]", timestamp: Date().addingTimeInterval(-20))
        let answerTurn = ConversationTurn(id: UUID(), source: .assistant, type: .answer, text: "Answer to 1st image", timestamp: Date().addingTimeInterval(-15))
        await manager.addTurn(imageTurn)
        await manager.addTurn(answerTurn)
        
        // When taking a second screenshot, there is no pending user query
        let query = await manager.getUnansweredUserQuery()
        XCTAssertNil(query, "Second image must not use previous assistant answer or [Image Analyzed] as query context")
    }

    func testContextManagerUnansweredQueryWithPendingQuery() async throws {
        let manager = ContextManager()
        
        // 1st image and answer
        await manager.addTurn(ConversationTurn(id: UUID(), source: .microphone, type: .question, text: "[Image Analyzed]", timestamp: Date().addingTimeInterval(-30)))
        await manager.addTurn(ConversationTurn(id: UUID(), source: .assistant, type: .answer, text: "Answer 1", timestamp: Date().addingTimeInterval(-25)))
        
        // User speaks before taking 2nd screenshot
        await manager.addTurn(ConversationTurn(id: UUID(), source: .microphone, type: .statement, text: "Can you solve problem 2?", timestamp: Date().addingTimeInterval(-5)))
        
        // Pending query should return the new question
        let query = await manager.getUnansweredUserQuery()
        XCTAssertNotNil(query)
        XCTAssertTrue(query?.contains("Can you solve problem 2?") == true)
        XCTAssertFalse(query?.contains("Answer 1") == true)
    }
}
