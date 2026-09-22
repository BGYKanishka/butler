import XCTest
@testable import butler

class MockLLMEngine: LLMEngine {
    var generatedText = "This is a mock suggestion."
    var isLoaded = false
    
    func load() async throws {
        isLoaded = true
    }
    
    func unload() {
        isLoaded = false
    }
    
    func generateStreaming(prompt: String, onToken: @escaping (String) -> Void) async throws {
        let words = generatedText.split(separator: " ")
        for word in words {
            onToken(String(word) + " ")
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    
    func cancel() {}
}

@MainActor
final class EndToEndFlowTests: XCTestCase {

    func testMicrophoneVoiceDoesNotTriggerSuggestion() async throws {
        let mockLLMEngine = MockLLMEngine()
        let environment = AppEnvironment(llmEngine: mockLLMEngine)
        let coordinator = SessionCoordinator(environment: environment)
        
        let expectation = XCTestExpectation(description: "LLM response should NOT complete")
        expectation.isInverted = true
        
        let cancellable = coordinator.overlayViewModel.$statusText.sink { status in
            if status == "Completed" {
                expectation.fulfill()
            }
        }
        
        // Microphone input should not trigger question detection
        coordinator.simulateSpeechDetected(text: "What is the capital of France?", source: .microphone)
        
        // Wait for debounce (0.5s) + safety margin to ensure no trigger occurred
        await fulfillment(of: [expectation], timeout: 1.5)
        cancellable.cancel()
        
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(coordinator.overlayViewModel.llmResponse, "The overlay should NOT contain suggested text for microphone input.")
    }
    
    func testSystemAudioTriggersSuggestion() async throws {
        let mockLLMEngine = MockLLMEngine()
        let environment = AppEnvironment(llmEngine: mockLLMEngine)
        let coordinator = SessionCoordinator(environment: environment)
        
        let expectation = XCTestExpectation(description: "LLM response completed")
        
        let cancellable = coordinator.overlayViewModel.$statusText.sink { status in
            if status == "Completed" {
                expectation.fulfill()
            }
        }
        
        coordinator.simulateSpeechDetected(text: "What is the capital of France?", source: .system)
        
        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()
        
        XCTAssertEqual(coordinator.state, .listening)
        XCTAssertTrue((coordinator.overlayViewModel.llmResponse ?? "").contains("mock suggestion"), "The overlay should contain the suggested text.")
    }
}
