import XCTest
@testable import Butler

final class PromptBuilderTests: XCTestCase {

    private func turn(_ text: String, _ source: AudioSource) -> ConversationTurn {
        ConversationTurn(id: UUID(), source: source, type: .statement, text: text, timestamp: Date())
    }

    func testProjectContextAppearsInPrompt() {
        let prompt = PromptBuilder().build(turns: [],
                                           projectSummary: "CANDIDATE'S PROJECT: \"Baleen Engine\"",
                                           question: "Tell me about Baleen", source: .system)
        XCTAssertTrue(prompt.contains("CANDIDATE'S PROJECT: \"Baleen Engine\""))
    }

    func testEmptySummaryDoesNotEmitEmptyProjectContextBlock() {
        let prompt = PromptBuilder().build(turns: [], projectSummary: "", question: "hi", source: .system)
        XCTAssertFalse(prompt.contains("PROJECT CONTEXT:\n"))
    }

    /// 100 retained turns used to be sent verbatim; a long interview overflowed the context window
    /// and the model silently stopped answering.
    func testOldTurnsAreDroppedToFitContextWindow() {
        let long = String(repeating: "word ", count: 400)
        let turns = (0..<100).map { turn("turn \($0) \(long)", $0 % 2 == 0 ? .system : .assistant) }
        let prompt = PromptBuilder().build(turns: turns, projectSummary: "ctx", question: "latest question?", source: .system)

        let config = LLMConfiguration()
        XCTAssertLessThan(PromptBuilder.estimateTokens(prompt), config.contextSize - config.maxTokens)
        XCTAssertTrue(prompt.contains("latest question?"))
        XCTAssertTrue(prompt.contains("turn 99"))       // newest kept
        XCTAssertFalse(prompt.contains("turn 0 "))      // oldest dropped
    }

    func testOversizedSummaryIsClampedIdenticallyEveryTime() {
        let huge = String(repeating: "PROJECT LINE\n", count: 20_000)
        let a = PromptBuilder().buildSystemPrefix(projectSummary: huge)
        let b = PromptBuilder().buildSystemPrefix(projectSummary: huge)
        XCTAssertEqual(a, b)   // KV-cache prefix must be byte-stable
        XCTAssertLessThan(PromptBuilder.estimateTokens(a), LLMConfiguration().contextSize)
    }
}
