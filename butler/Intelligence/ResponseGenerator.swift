import Foundation
import os

private let logger = Logger(subsystem: "com.butler", category: "Intelligence")

/// Handles intent detection and response streaming from the LLM.
///
/// Pinned to the main actor so that `isEvaluating` and the callback
/// closures are always touched on one thread, eliminating the race
/// where two transcripts arriving in quick succession could both slip
/// past the `guard !isEvaluating` check before either set it to true.
@MainActor
final class ResponseGenerator {
    private let contextManager: ContextManager
    private let projectContextManager: ProjectContextManager?
    private let promptBuilder: PromptBuilder
    private let llmEngine: LLMEngine
    private let projectRetriever: ProjectRetrievalService?
    private var currentGenerationTask: Task<Void, Never>?
    private var isEvaluating: Bool = false

    // Parsing state for the current generation
    private var buffer = ""
    private var decisionMade = false
    private var isIntentValid = false
    private var strippedLeadingNoise = false

    // Loop protection for the current generation (see RepetitionGuard).
    private var repetitionGuard = RepetitionGuard()
    private var stoppedForRepetition = false

    /// Latest FINAL transcript that arrived while another evaluation was running. It used to be
    /// discarded, so a question asked right after another one could be lost without any trace.
    private var pendingTranscript: (text: String, source: AudioSource)?

    var onIntentConfirmed: (@MainActor (String) -> Void)?
    var onTokenGenerated: (@MainActor (String) -> Void)?
    var onResponseCompleted: (@MainActor () -> Void)?
    var onResponseIgnored: (@MainActor () -> Void)?

    init(contextManager: ContextManager, projectContextManager: ProjectContextManager? = nil, promptBuilder: PromptBuilder, llmEngine: LLMEngine, projectRetriever: ProjectRetrievalService? = nil) {
        self.contextManager = contextManager
        self.projectContextManager = projectContextManager
        self.promptBuilder = promptBuilder
        self.llmEngine = llmEngine
        self.projectRetriever = projectRetriever
    }

    func handleTranscript(_ transcript: String, source: AudioSource, isFinal: Bool = true) {
        guard !isEvaluating else {
            if isFinal { pendingTranscript = (transcript, source) }
            return
        }
        isEvaluating = true

        currentGenerationTask = Task { [weak self] in
            guard let self = self else { return }
            let turns = await self.contextManager.getRecentTurns()
            let projectSummary = self.projectContextManager?.currentContext?.summary
            logger.info("Project context in prompt: \(projectSummary?.count ?? 0) chars (manager attached: \(self.projectContextManager != nil))")
            
            var retrieved = ""
            if projectSummary != nil, let r = self.projectRetriever, UserDefaults.standard.bool(forKey: ConfigKey.projectRetrievalEnabled) {
                let budget = PromptBuilder.retrievalTokenBudget(contextSize: LLMConfiguration().contextSize)
                let t0 = CFAbsoluteTimeGetCurrent()
                retrieved = await withTaskGroup(of: String.self) { group in
                    group.addTask {
                        return await r.context(for: transcript, recentTurns: turns, isFinal: isFinal, budgetTokens: budget)
                    }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        return ""
                    }
                    for await res in group {
                        group.cancelAll()
                        return res
                    }
                    return ""
                }
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                logger.info("Retrieved context: \(retrieved.count > 0 ? "YES" : "NO") in \(ms)ms")
                // Which files did the answer actually get to see? ContextAssembler headers look like "[1] path/File.swift:10-40 Symbol".
                let sources = retrieved.components(separatedBy: "\n")
                    .filter { $0.hasPrefix("[") && $0.dropFirst().first?.isNumber == true }
                    .prefix(8).joined(separator: " | ")
                if !sources.isEmpty { logger.info("Retrieved sources: \(sources)") }
            }
            
            let prompt = self.promptBuilder.build(turns: turns, projectSummary: projectSummary, retrievedContext: retrieved, question: transcript, source: source)

            self.buffer = ""
            self.decisionMade = false
            self.isIntentValid = false
            self.strippedLeadingNoise = false
            self.repetitionGuard = RepetitionGuard()
            self.stoppedForRepetition = false
            logger.info("Prompt ≈ \(PromptBuilder.estimateTokens(prompt)) tokens, history turns: \(turns.count), retrieved chars: \(retrieved.count)")

            do {
                try await self.llmEngine.generateStreaming(prompt: prompt) { [weak self] token in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }

                        if !self.decisionMade {
                            self.buffer += token
                            let trimmedUpper = self.buffer.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

                            if trimmedUpper.hasPrefix("YES") {
                                self.decisionMade = true
                                self.isIntentValid = true
                                self.onIntentConfirmed?(transcript)

                                var remaining = self.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                if remaining.uppercased().hasPrefix("YES|") {
                                    remaining = String(remaining.dropFirst(4))
                                } else if remaining.uppercased().hasPrefix("YES") {
                                    remaining = String(remaining.dropFirst(3))
                                }

                                remaining = remaining.trimmingCharacters(in: CharacterSet(charactersIn: " |:\n\t"))

                                if !remaining.isEmpty {
                                    self.strippedLeadingNoise = true
                                    self.emit(remaining)
                                }
                            } else if trimmedUpper.hasPrefix("NO") {
                                self.decisionMade = true
                                self.isIntentValid = false
                                self.llmEngine.cancel()
                            } else if self.buffer.count > 20 {
                                // Model skipped YES/NO — assume it's answering directly.
                                self.decisionMade = true
                                self.isIntentValid = true
                                self.strippedLeadingNoise = true
                                self.onIntentConfirmed?(transcript)
                                self.emit(self.buffer)
                            }
                        } else if self.isIntentValid {
                            if !self.strippedLeadingNoise {
                                let noiseChars = CharacterSet(charactersIn: " |:\n\t")
                                let trimmedToken = token.trimmingCharacters(in: noiseChars)
                                if !trimmedToken.isEmpty {
                                    self.strippedLeadingNoise = true
                                    if let idx = token.firstIndex(where: { !noiseChars.contains($0.unicodeScalars.first!) }) {
                                        self.emit(String(token[idx...]))
                                    } else {
                                        self.emit(trimmedToken)
                                    }
                                }
                            } else if !self.stoppedForRepetition {
                                self.emit(token)
                            }
                        }
                    }
                }

                if self.isIntentValid {
                    self.onResponseCompleted?()
                } else {
                    logger.debug("LLM classified transcript as non-actionable (NO)")
                    self.onResponseIgnored?()
                }
            } catch {
                // Generation errors are non-fatal; the session stays active.
                logger.error("LLM generation failed: \(error.localizedDescription)")
            }

            self.isEvaluating = false

            // A question that arrived mid-evaluation is only replayed when nothing was answered:
            // if an answer was just shown, the normal cooldown rules apply and the user can ask again.
            if let next = self.pendingTranscript {
                self.pendingTranscript = nil
                if !self.isIntentValid {
                    self.handleTranscript(next.text, source: next.source)
                }
            }
        }
    }

    /// Single exit for answer text: forwards it to the UI and cancels the generation if the model
    /// starts repeating itself.
    private func emit(_ text: String) {
        onTokenGenerated?(text)
        guard !stoppedForRepetition, repetitionGuard.shouldStop(after: text) else { return }
        stoppedForRepetition = true
        logger.warning("Repetition loop detected — cancelling generation")
        llmEngine.cancel()
    }
}
