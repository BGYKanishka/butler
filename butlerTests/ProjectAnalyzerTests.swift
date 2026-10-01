import XCTest
@testable import Butler

final class ProjectAnalyzerTests: XCTestCase {
    
    func testVocabularyExtraction() async throws {
        // Setup a temporary directory for our mock project
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? fileManager.removeItem(at: tempDir)
        }
        
        // Create mock files
        let files = [
            "LocalLLMEngine.swift",
            "BaleenModel.swift",
            "WhisperWrapper.mm",
            "package.json",
            "main.swift"
        ]
        
        for file in files {
            let fileURL = tempDir.appendingPathComponent(file)
            try "mock content".write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        let analyzer = ProjectAnalyzer()
        let context = try await analyzer.analyzeProject(at: tempDir)
        
        // Check vocabulary extraction
        XCTAssertTrue(context.vocabulary.contains("LocalLLMEngine"))
        XCTAssertTrue(context.vocabulary.contains("BaleenModel"))
        XCTAssertTrue(context.vocabulary.contains("WhisperWrapper"))
        
        // Check summary contents
        XCTAssertTrue(context.summary.contains("PROJECT VOCABULARY"))
        XCTAssertTrue(context.summary.contains("LocalLLMEngine"))
        XCTAssertTrue(context.summary.contains("Swift"))
        XCTAssertTrue(context.summary.contains("Node.js"))
    }

    // MARK: - Regression tests for "Butler doesn't know my project"

    /// A Go project (no Swift/JS files) used to contribute ZERO terms to the vocabulary and no
    /// project name, so Whisper/LLM never saw "Baleen".
    func testGoProjectNameSymbolsAndDependenciesAreCaptured() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("baleen-engine")
        try fm.createDirectory(at: root.appendingPathComponent("cmd/baleen"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("internal/network"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root.deletingLastPathComponent()) }

        try "module github.com/someone/baleen-engine\n\ngo 1.22\n\nrequire (\n\tgithub.com/grandcat/zeroconf v1.0.0\n\tgo.etcd.io/bbolt v1.4.3\n)\n"
            .write(to: root.appendingPathComponent("go.mod"), atomically: true, encoding: .utf8)
        try "# Baleen Engine 🐳\n\nPeer-to-peer Docker image sharing using `zeroconf`.\n"
            .write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "package main\n\nfunc main() {}\n"
            .write(to: root.appendingPathComponent("cmd/baleen/main.go"), atomically: true, encoding: .utf8)
        try "package network\n\ntype PeerRegistry struct{}\n\nfunc NewPeerRegistry() *PeerRegistry { return nil }\n"
            .write(to: root.appendingPathComponent("internal/network/peer_registry.go"), atomically: true, encoding: .utf8)

        let context = try await ProjectAnalyzer().analyzeProject(at: root)

        XCTAssertTrue(context.projectNames.contains("Baleen Engine"))
        XCTAssertTrue(context.projectNames.contains("Baleen"))
        XCTAssertTrue(context.vocabulary.contains("PeerRegistry"))
        XCTAssertTrue(context.vocabulary.contains("zeroconf"))
        XCTAssertTrue(context.vocabulary.contains("bbolt"))
        XCTAssertTrue(context.summary.contains("CANDIDATE'S PROJECT: \"Baleen Engine\""))
        XCTAssertTrue(context.summary.contains("Go"))

        // Whisper must be primed with the project name, first.
        XCTAssertTrue(context.makeWhisperPrompt().hasPrefix("Technical interview about Baleen Engine"))
    }

    /// The summary must always fit the LLM context window (the old one was ~14k tokens vs 8k window).
    func testSummaryRespectsBudgetOnLargeProjects() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let big = String(repeating: "func Exported() {}\n// filler filler filler\n", count: 150)
        for i in 0..<120 {
            try big.write(to: root.appendingPathComponent("file_\(i).go"), atomically: true, encoding: .utf8)
        }

        let budget = 8_000
        let context = try await ProjectAnalyzer().analyzeProject(at: root, summaryBudget: budget)
        XCTAssertLessThanOrEqual(context.summary.count, budget + 200)
    }

    func testProjectContextDataSurvivesJSONRoundTrip() throws {
        let original = ProjectContextData(vocabulary: ["bbolt"], summary: "CANDIDATE'S PROJECT: X", projectNames: ["X"])
        let decoded = try JSONDecoder().decode(ProjectContextData.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(original, decoded)
    }
}
