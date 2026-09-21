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

final class EndToEndFlowTests: XCTestCase {

    func testMicrophoneVoiceTriggersSuggestion() async throws {
        let mockLLMEngine = MockLLMEngine()
        let environment = AppEnvironment(llmEngine: mockLLMEngine)
        let coordinator = SessionCoordinator(environment: environment)
        
        let expectation = XCTestExpectation(description: "LLM response completed")
        
        // Mock the response generator's completion block or observe overlayViewModel
        let cancellable = coordinator.overlayViewModel.$statusText.sink { status in
            if status == "Completed" {
                expectation.fulfill()
            }
        }
        
        // Wait, the SessionCoordinator doesn't need to load engines if we just simulate speech, BUT the ResponseGenerator will try to use llmEngine.
        // Also simulateSpeechDetected relies on state == .listening to process audio if testing audio directly, but simulateSpeechDetected bypasses the state check.
        // But for mockLLMEngine, since the LLMEngine does not throw if not loaded, it will just work! Wait, our mock doesn't throw if not loaded.
        
        // Since we changed QuestionDetector to also accept .microphone, let's test it:
        coordinator.simulateSpeechDetected(text: "What is the capital of France?", source: .microphone)
        
        // We wait for the debounce of QuestionDetector (0.5s) and the generation duration
        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()
        
        XCTAssertEqual(coordinator.state, .listening)
        // Check that overlay text has our mock generated text
        XCTAssertTrue((coordinator.overlayViewModel.llmResponse ?? "").contains("mock suggestion"), "The overlay should contain the suggested text.")
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
