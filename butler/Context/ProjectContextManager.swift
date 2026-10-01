import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.butler", category: "ProjectContext")

/// Everything needed to rebuild the LLM prompt after an app restart.
///
/// The old implementation persisted only the vocabulary and restored `summary: ""`, so after any
/// relaunch the model's system prompt contained an empty PROJECT CONTEXT and Butler had "no idea"
/// what the user's project was. The KV-cache file cannot substitute for this: the prompt is rebuilt
/// from text for every question, and a cache is only reused when the prompt text matches it.
private struct PersistedProjectContext: Codable {
    var version: Int
    var projectPaths: [String]
    var analyzedAt: Date
    var context: ProjectContextData
}

class ProjectContextManager: ObservableObject {
    private static let snapshotVersion = 2

    @Published var currentContext: ProjectContextData?
    @Published var isAnalyzing = false
    @Published var projectURLs: [URL] = []
    @Published var indexState: IndexState = .idle

    /// True when the project list changed (or no saved analysis exists) and the LLM would
    /// currently have no / stale project context. Surfaced in Settings.
    @Published var needsReanalysis = false

    private let analyzer: ProjectAnalyzerService
    private let llmEngine: LLMEngine?
    private let indexCoordinator: ProjectIndexCoordinator?

    init(analyzer: ProjectAnalyzerService = ProjectAnalyzer(), llmEngine: LLMEngine? = nil, indexCoordinator: ProjectIndexCoordinator? = nil) {
        self.analyzer = analyzer
        self.llmEngine = llmEngine
        self.indexCoordinator = indexCoordinator
    }

    /// Set by SessionCoordinator so analysis can check whether a session is running
    /// before overwriting the shared binary KV-cache.
    var isSessionActive: (() -> Bool)?

    var binaryStatePath: String {
        return Constants.projectMemoryStatePath
    }

    private var snapshotURL: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent(Constants.appSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("project_context.json")
    }

    // MARK: - Project list

    func addProject(_ url: URL) {
        if !projectURLs.contains(url) {
            projectURLs.append(url)
            saveProjectURLs(projectURLs)
            needsReanalysis = true
        }
    }

    func removeProject(at index: IndexSet) {
        let toRemove = index.map { projectURLs[$0] }
        projectURLs.remove(atOffsets: index)
        saveProjectURLs(projectURLs)
        
        for url in toRemove {
            Task {
                await indexCoordinator?.removeProject(root: url)
            }
        }
        
        if projectURLs.isEmpty {
            clearProject()
        } else {
            needsReanalysis = true
        }
    }

    // MARK: - Analysis

    /// - Parameter warmCache: also pre-compute and save the llama.cpp KV-cache for the project prefix.
    ///   This is only a latency optimisation; answers are correct without it.
    func analyzeProjects(warmCache: Bool = true) {
        let urls = projectURLs
        if urls.isEmpty { return }
        Task {
            logger.info("Starting project analysis")
            await MainActor.run { self.isAnalyzing = true }
            do {
                // Split one context-window-sized budget between all projects.
                let totalBudget = PromptBuilder.summaryCharBudget(contextSize: LLMConfiguration().contextSize)
                let perProject = max(totalBudget / max(urls.count, 1), 2_500)

                var perProjectVocab = [[String]]()
                var names = [String]()
                var summaries = [String]()

                for url in urls {
                    let context = try await analyzer.analyzeProject(at: url, summaryBudget: perProject)
                    perProjectVocab.append(context.vocabulary)
                    names.append(contentsOf: context.projectNames)
                    summaries.append(context.summary)
                }

                var vocab = [String](); var seen = Set<String>()
                let longest = perProjectVocab.map { $0.count }.max() ?? 0
                for i in 0..<longest {                       // round-robin so every project is represented
                    for list in perProjectVocab where i < list.count {
                        if seen.insert(list[i].lowercased()).inserted { vocab.append(list[i]) }
                    }
                }

                let finalContext = ProjectContextData(
                    vocabulary: Array(vocab.prefix(150)),
                    summary: summaries.joined(separator: "\n\n"),
                    projectNames: names
                )

                // Persist + publish BEFORE the slow/fragile KV-cache step so a failure there
                // can never lose the analysis.
                self.persist(finalContext, paths: urls.map { $0.path })
                await MainActor.run {
                    self.currentContext = finalContext
                    self.needsReanalysis = false
                    UserDefaults.standard.set(finalContext.makeWhisperPrompt(), forKey: ConfigKey.whisperVocabulary)
                    logger.info("Project analysis finished: \(finalContext.summary.count) chars, \(finalContext.vocabulary.count) terms")
                }
                
                if let coordinator = self.indexCoordinator {
                    Task(priority: .utility) {
                        await coordinator.sync(projects: urls)
                    }
                }

                if warmCache, let engine = self.llmEngine {
                    if self.isSessionActive?() == true {
                        logger.warning("Skipping KV-cache write — session is active.")
                    } else {
                        do {
                            let prefix = PromptBuilder().buildSystemPrefix(projectSummary: finalContext.summary)
                            try await engine.load()
                            try await engine.saveState(to: self.binaryStatePath, prompt: prefix)
                            // Don't leave a multi-GB model resident when nobody is using it; the
                            // next session's load() restores this state from disk.
                            if self.isSessionActive?() != true { await engine.unload() }
                        } catch {
                            logger.error("KV-cache warm-up failed (answers still work, first reply is slower): \(error.localizedDescription)")
                            try? FileManager.default.removeItem(atPath: self.binaryStatePath)
                        }
                    }
                }

                await MainActor.run { self.isAnalyzing = false }
            } catch {
                logger.error("Failed to analyse projects: \(error.localizedDescription)")
                await MainActor.run { self.isAnalyzing = false }
            }
        }
    }

    func clearProject() {
        for url in projectURLs {
            Task {
                await indexCoordinator?.removeProject(root: url)
            }
        }
        currentContext = nil
        projectURLs = []
        needsReanalysis = false
        saveProjectURLs([])
        UserDefaults.standard.removeObject(forKey: ConfigKey.whisperVocabulary)
        if let url = snapshotURL { try? FileManager.default.removeItem(at: url) }
        if FileManager.default.fileExists(atPath: binaryStatePath) {
            try? FileManager.default.removeItem(atPath: binaryStatePath)
        }
    }

    // MARK: - Persistence

    private func saveProjectURLs(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        UserDefaults.standard.set(paths, forKey: ConfigKey.projectPaths)
    }

    private func persist(_ context: ProjectContextData, paths: [String]) {
        guard let url = snapshotURL else { return }
        let payload = PersistedProjectContext(version: Self.snapshotVersion, projectPaths: paths,
                                              analyzedAt: Date(), context: context)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(payload).write(to: url, options: .atomic)
        } catch {
            logger.error("Could not persist project context: \(error.localizedDescription)")
        }
    }

    private func loadSnapshot() -> PersistedProjectContext? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistedProjectContext.self, from: data)
    }

    func restoreSavedProjects() {
        guard let paths = UserDefaults.standard.stringArray(forKey: ConfigKey.projectPaths),
              !paths.isEmpty else { return }

        projectURLs = paths.map { URL(fileURLWithPath: $0) }

        if let saved = loadSnapshot(), saved.version == Self.snapshotVersion, saved.projectPaths == paths {
            // Full context restored, including the summary text the LLM actually needs.
            currentContext = saved.context
            needsReanalysis = false
            UserDefaults.standard.set(saved.context.makeWhisperPrompt(), forKey: ConfigKey.whisperVocabulary)
            logger.info("Restored project context (\(saved.context.summary.count) chars)")
            
            if let coordinator = self.indexCoordinator {
                Task(priority: .utility) {
                    await coordinator.sync(projects: self.projectURLs)
                }
            }
        } else {
            // First launch after this fix (or the project list changed): there is no trustworthy
            // summary. Rebuild it now — text analysis only, it is fast and needs no model.
            currentContext = nil
            needsReanalysis = true
            logger.warning("No saved project analysis — rebuilding in the background")
            analyzeProjects(warmCache: false)
        }
    }
}
