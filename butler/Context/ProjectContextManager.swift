import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.butler", category: "ProjectContext")

class ProjectContextManager: ObservableObject {
    @Published var currentContext: ProjectContextData?
    @Published var isAnalyzing = false
    @Published var projectURLs: [URL] = []
    
    private let analyzer: ProjectAnalyzerService
    private let llmEngine: LLMEngine?
    
    init(analyzer: ProjectAnalyzerService = ProjectAnalyzer(), llmEngine: LLMEngine? = nil) {
        self.analyzer = analyzer
        self.llmEngine = llmEngine
    }
    
    var binaryStatePath: String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("butler_project_memory.bin").path
    }
    
    func addProject(_ url: URL) {
        if !projectURLs.contains(url) {
            projectURLs.append(url)
            saveProjectURLs(projectURLs)
        }
    }
    
    func removeProject(at index: IndexSet) {
        projectURLs.remove(atOffsets: index)
        saveProjectURLs(projectURLs)
        if projectURLs.isEmpty {
            clearProject()
        }
    }
    
    func analyzeProjects() {
        let urls = projectURLs
        if urls.isEmpty { return }
        Task {
            logger.info("Starting project analysis")
            await MainActor.run { self.isAnalyzing = true }
            do {
                var combinedVocabulary = Set<String>()
                var combinedSummaries = [String]()
                
                for url in urls {
                    let context = try await analyzer.analyzeProject(at: url)
                    combinedVocabulary.formUnion(context.vocabulary)
                    combinedSummaries.append(context.summary)
                }
                
                let mergedSummary = combinedSummaries.joined(separator: "\n")
                let finalContext = ProjectContextData(vocabulary: Array(combinedVocabulary), summary: mergedSummary)
                
                // Build and save binary memory
                if let engine = self.llmEngine {
                    let prefix = PromptBuilder().buildSystemPrefix(projectSummary: mergedSummary)
                    
                    // We must ensure the engine is loaded before saving state
                    try? await engine.load()
                    try? await engine.saveState(to: self.binaryStatePath, prompt: prefix)
                }
                
                await MainActor.run {
                    logger.info("Project analysis finished")
                    self.currentContext = finalContext
                    self.isAnalyzing = false
                    
                    // Save vocabulary to UserDefaults for WhisperEngine to pick up
                    let vocabString = finalContext.vocabulary.joined(separator: ", ")
                    UserDefaults.standard.set(vocabString, forKey: ConfigKey.whisperVocabulary)
                }
            } catch {
                logger.error("Failed to analyse projects: \(error.localizedDescription)")
                await MainActor.run {
                    self.isAnalyzing = false
                    logger.debug("Analysis finished with error")
                }
            }
        }
    }
    
    func clearProject() {
        currentContext = nil
        projectURLs = []
        saveProjectURLs([])
        if FileManager.default.fileExists(atPath: binaryStatePath) {
            try? FileManager.default.removeItem(atPath: binaryStatePath)
        }
    }
    
    private func saveProjectURLs(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        UserDefaults.standard.set(paths, forKey: ConfigKey.projectPaths)
    }
    
    func restoreSavedProjects() {
        if let paths = UserDefaults.standard.stringArray(forKey: ConfigKey.projectPaths) {
            let urls = paths.map { URL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                self.projectURLs = urls
                // Assume binary state exists, no need to re-analyze unless explicitly requested
                // But we need the vocabulary loaded
                let vocabString = UserDefaults.standard.string(forKey: ConfigKey.whisperVocabulary) ?? ""
                let vocab = vocabString.components(separatedBy: ", ")
                self.currentContext = ProjectContextData(vocabulary: vocab, summary: "")
            }
        }
    }
}
