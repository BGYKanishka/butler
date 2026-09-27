import XCTest
@testable import butler

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
}
