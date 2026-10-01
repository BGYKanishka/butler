import Foundation

// MARK: - Service protocol

protocol ProjectAnalyzerService: Sendable {
    func analyzeProject(at url: URL) async throws -> ProjectContextData
    func analyzeProject(at url: URL, summaryBudget: Int) async throws -> ProjectContextData
}

extension ProjectAnalyzerService {
    func analyzeProject(at url: URL, summaryBudget: Int) async throws -> ProjectContextData {
        try await analyzeProject(at: url)
    }
}

// MARK: - Analyzer

actor ProjectAnalyzer: ProjectAnalyzerService {

    func analyzeProject(at url: URL) async throws -> ProjectContextData {
        let budget = PromptBuilder.summaryCharBudget(contextSize: LLMConfiguration().contextSize)
        return try await analyzeProject(at: url, summaryBudget: budget)
    }

    func analyzeProject(at url: URL, summaryBudget: Int) async throws -> ProjectContextData {
        ProjectScanner.analyze(root: url, budget: summaryBudget)
    }
}
