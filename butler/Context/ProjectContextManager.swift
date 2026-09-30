import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.butler", category: "ProjectContext")

class ProjectContextManager: ObservableObject {
    @Published var currentContext: ProjectContextData?
    @Published var isAnalyzing = false
    @Published var projectURLs: [URL] = []

    /// When true the binary KV-cache state is missing or stale and the
    /// user should be asked to re-analyse before starting a session.
    @Published var needsReanalysis = false

    private let analyzer: ProjectAnalyzerService
    private let llmEngine: LLMEngine?

    init(analyzer: ProjectAnalyzerService = ProjectAnalyzer(), llmEngine: LLMEngine? = nil) {
        self.analyzer = analyzer
        self.llmEngine = llmEngine
    }

    /// Set by SessionCoordinator so analysis can check whether a session is running
    /// before overwriting the shared binary KV-cache.
    var isSessionActive: (() -> Bool)?

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

                // Build and cache binary KV-state for faster session start.
                // Skip if a session is active — writing the state file while the
                // LLM is running would corrupt the binary KV-cache mid-session.
                if let engine = self.llmEngine {
                    if self.isSessionActive?() == true {
                        logger.warning("Skipping KV-cache write — session is active. Re-analyse after stopping the session to persist project memory.")
                    } else {
                        let prefix = PromptBuilder().buildSystemPrefix(projectSummary: mergedSummary)
                        try? await engine.load()
                        try? await engine.saveState(to: self.binaryStatePath, prompt: prefix)
                    }
                }

                await MainActor.run {
                    logger.info("Project analysis finished")
                    self.currentContext = finalContext
                    self.needsReanalysis = false
                    self.isAnalyzing = false

                    // Persist vocabulary so WhisperEngine can use it on next launch.
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
        needsReanalysis = false
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
        guard let paths = UserDefaults.standard.stringArray(forKey: ConfigKey.projectPaths),
              !paths.isEmpty else { return }

        let urls = paths.map { URL(fileURLWithPath: $0) }
        self.projectURLs = urls

        // Rebuild vocabulary from UserDefaults so Whisper is ready immediately.
        let vocabString = UserDefaults.standard.string(forKey: ConfigKey.whisperVocabulary) ?? ""
        let vocab = vocabString.components(separatedBy: ", ").filter { !$0.isEmpty }

        let binaryExists = FileManager.default.fileExists(atPath: binaryStatePath)

        if binaryExists {
            // Full context available — restore with the real summary from the
            // saved state. Summary text is not persisted separately, but the
            // binary KV-state captures it implicitly, so we pass an empty
            // placeholder that will be ignored once the state is loaded at
            // session start.
            self.currentContext = ProjectContextData(vocabulary: vocab, summary: "")
            self.needsReanalysis = false
        } else {
            // Binary state is gone (e.g. app reinstall, manual cleanup).
            // Keep the project list so the UI stays populated, but flag that
            // the user needs to re-analyse before the LLM will have context.
            self.currentContext = ProjectContextData(vocabulary: vocab, summary: "")
            self.needsReanalysis = true
            logger.warning("Binary state missing — re-analysis required before starting a session")
        }
    }
}
