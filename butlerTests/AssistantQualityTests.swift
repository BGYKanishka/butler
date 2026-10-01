import XCTest
@testable import Butler

/// Regression tests for the "Butler answers about llama.cpp instead of my project, in long
/// repeating paragraphs" problem. Each test maps to one root cause found in the session log.
final class AssistantQualityTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject(_ files: [String: String]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("proj")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        return root.resolvingSymlinksInPath()
    }

    private func turn(_ text: String, _ source: AudioSource) -> ConversationTurn {
        ConversationTurn(id: UUID(), source: source, type: .statement, text: text, timestamp: Date())
    }

    // MARK: - Root cause 1: vendored code was indexed as the user's project

    func testCapitalisedVendorDirectoryIsIgnored() throws {
        let root = try makeProject([
            "Vendor/llama.cpp/src/llama.cpp": "int llama_decode() { return 0; }",
            "butler/App/AppDelegate.swift": "final class AppDelegate {}",
        ])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let paths = ProjectScanner.scanFiles(root: root).map { $0.path }
        XCTAssertTrue(paths.contains("butler/App/AppDelegate.swift"))
        XCTAssertFalse(paths.contains { $0.hasPrefix("Vendor/") }, "Vendor/ must be skipped regardless of case")
    }

    func testGitSubmodulesAreSkippedButIndependentClonesAreKept() throws {
        let root = try makeProject([
            "Libs/Inner/.git": "gitdir: ../../.git/modules/Inner",   // a FILE => submodule
            "Libs/Inner/Inner.swift": "struct Inner {}",
            "Libs/Own.swift": "struct Own {}",
            "Clone/.git/HEAD": "ref: refs/heads/main",                // a DIRECTORY => normal clone
            "Clone/Clone.swift": "struct Clone {}",
        ])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let paths = ProjectScanner.scanFiles(root: root).map { $0.path }
        XCTAssertTrue(paths.contains("Libs/Own.swift"))
        XCTAssertFalse(paths.contains("Libs/Inner/Inner.swift"), "submodules are not the user's code")
        XCTAssertTrue(paths.contains("Clone/Clone.swift"), "independent clones must still be scanned")
    }

    func testFirstPartyCodeIsNotSortedBehindCapitalisedDirectories() throws {
        let root = try makeProject([
            "Scripts/build.sh": "echo hi",
            "butler/Main.swift": "print(1)",
        ])
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let paths = ProjectScanner.scanFiles(root: root).map { $0.path }
        let butlerIndex = try XCTUnwrap(paths.firstIndex(of: "butler/Main.swift"))
        let scriptsIndex = try XCTUnwrap(paths.firstIndex(of: "Scripts/build.sh"))
        XCTAssertLessThan(butlerIndex, scriptsIndex)
    }

    // MARK: - Root cause 2: looping output

    func testRepetitionGuardStopsNearDuplicateLoop() {
        let loop = """
        The llm_graph_context object is used to manage the graph during inference, and the graph object is used to represent the computational graph of the neural network. \
        The llm_graph_params object is used to specify the parameters for the graph, such as the model and the parameters for the graph itself. \
        The llm_graph_context object is used to manage the graph during inference, and the graph object is used to represent the computational graph of the neural network. \
        The llm_graph_params object is used to specify the parameters for the graph, such as the model and the parameters for the graph itself. \
        The llm_graph_context object is used to manage the graph during inference, and the graph object is used to represent the computational graph of the neural network.
        """
        var guardState = RepetitionGuard()
        var stopped = false
        for word in loop.split(separator: " ") {
            if guardState.shouldStop(after: String(word) + " ") { stopped = true; break }
        }
        XCTAssertTrue(stopped)
    }

    func testRepetitionGuardAllowsNormalBulletAnswer() {
        let good = """
        **Butler answers from your codebase using hybrid retrieval.**
        - **Index:** ProjectIndexCoordinator chunks files into SQLite FTS5
        - **Route:** QueryRouter finds symbols, file names and keywords
        - **Fuse:** HybridProjectRetriever merges symbol, path and lexical hits with RRF
        - **Assemble:** ContextAssembler fits chunks to the token budget
        """
        var guardState = RepetitionGuard()
        for word in good.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            XCTAssertFalse(guardState.shouldStop(after: String(word) + " "))
        }
    }

    // MARK: - Root cause 3: speech-to-text mishearings

    func testTranscriptCorrectorFixesRagMishearingsWhenProjectHasRetrieval() {
        let corrector = TranscriptCorrector()
        corrector.update(vocabulary: ["Hybrid Retrieval System", "Butler"])

        XCTAssertEqual(corrector.correct("I mean how Butler use frag system."), "I mean how Butler use RAG system.")
        XCTAssertEqual(corrector.correct("how it use regsystem to give answers"), "how it use RAG system to give answers")
        XCTAssertEqual(corrector.correct("Butler's Rack System, that in Project Analyze part."), "Butler's RAG System, that in Project Analyze part.")
    }

    func testTranscriptCorrectorLeavesUnrelatedProjectsAlone() {
        let corrector = TranscriptCorrector()
        corrector.update(vocabulary: ["Audio Capture", "Mixer"])
        XCTAssertEqual(corrector.correct("the rack system is loud"), "the rack system is loud")
        XCTAssertEqual(corrector.correct("a regular system"), "a regular system")
    }

    func testTranscriptCorrectorFixesGeneralTechTerms() {
        let corrector = TranscriptCorrector()
        XCTAssertEqual(corrector.correct("is the KV cash saved"), "is the KV cache saved")
        XCTAssertEqual(corrector.correct("we use sequel lite"), "we use SQLite")
    }

    func testConceptExpanderMapsRagToRetrievalComponents() {
        XCTAssertTrue(ConceptExpander.keywords(forWords: ["how", "rag", "system"]).contains("retriev"))
        XCTAssertTrue(ConceptExpander.keywords(forWords: ["project", "analyze", "part"]).contains("analyz"))
        XCTAssertTrue(ConceptExpander.keywords(forWords: ["good", "morning"]).isEmpty)
    }

    // MARK: - Root cause 4: prompt construction

    func testCurrentQuestionAppearsOnceNotTwice() {
        let question = "How does the RAG system work?"
        let prompt = PromptBuilder().build(turns: [turn(question, .microphone)], projectSummary: "ctx",
                                           question: question, source: .microphone)
        XCTAssertEqual(prompt.components(separatedBy: question).count - 1, 1)
    }

    func testPromptCarriesFormatContractAndSpeakerLabels() {
        let prompt = PromptBuilder().build(turns: [], projectSummary: "ctx", question: "Explain it", source: .system)
        XCTAssertTrue(prompt.contains("ANSWER FORMAT"))
        XCTAssertTrue(prompt.contains("[OTHER PARTY]: Explain it"))
        XCTAssertTrue(prompt.contains("No paragraphs"))
    }

    func testOldAssistantAnswersAreClippedAndLimited() {
        var turns = [ConversationTurn]()
        for i in 1...5 {
            turns.append(turn("question \(i)", .microphone))
            turns.append(turn("ANSWER\(i) " + String(repeating: "word ", count: 1000), .assistant))
        }
        let prompt = PromptBuilder().build(turns: turns, projectSummary: "ctx", question: "latest?", source: .microphone)

        XCTAssertFalse(prompt.contains("ANSWER1"))
        XCTAssertFalse(prompt.contains("ANSWER3"))
        XCTAssertTrue(prompt.contains("ANSWER5"))
        XCTAssertFalse(prompt.contains(String(repeating: "word ", count: 300)), "history answers must be clipped")
    }

    // MARK: - Root cause 5: stale settings truncating answers

    func testTinyStoredMaxTokensIsIgnored() {
        let key = ConfigKey.llmMaxTokens
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original { UserDefaults.standard.set(original, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(230, forKey: key)
        XCTAssertEqual(LLMConfiguration().maxTokens, LLMConfiguration().activeProfile.configuration.maxTokens)
        UserDefaults.standard.set(900, forKey: key)
        XCTAssertEqual(LLMConfiguration().maxTokens, 900)
    }
}
