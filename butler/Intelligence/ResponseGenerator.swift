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
    private var currentGenerationTask: Task<Void, Never>?
    private var isEvaluating: Bool = false

    // Parsing state for the current generation
    private var buffer = ""
    private var decisionMade = false
    private var isIntentValid = false
    private var strippedLeadingNoise = false

    var onIntentConfirmed: (@MainActor (String) -> Void)?
    var onTokenGenerated: (@MainActor (String) -> Void)?
    var onResponseCompleted: (@MainActor () -> Void)?
    var onResponseIgnored: (@MainActor () -> Void)?

    init(contextManager: ContextManager, projectContextManager: ProjectContextManager? = nil, promptBuilder: PromptBuilder, llmEngine: LLMEngine) {
        self.contextManager = contextManager
        self.projectContextManager = projectContextManager
        self.promptBuilder = promptBuilder
        self.llmEngine = llmEngine
    }

    func handleTranscript(_ transcript: String, source: AudioSource) {
        guard !isEvaluating else { return }
        isEvaluating = true

        currentGenerationTask = Task { [weak self] in
            guard let self = self else { return }
            let turns = await self.contextManager.getRecentTurns()
            let projectSummary = self.projectContextManager?.currentContext?.summary
            let prompt = self.promptBuilder.build(turns: turns, projectSummary: projectSummary, question: transcript, source: source)

            self.buffer = ""
            self.decisionMade = false
            self.isIntentValid = false
            self.strippedLeadingNoise = false

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
                                    self.onTokenGenerated?(remaining)
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
                                self.onTokenGenerated?(self.buffer)
                            }
                        } else if self.isIntentValid {
                            if !self.strippedLeadingNoise {
                                let noiseChars = CharacterSet(charactersIn: " |:\n\t")
                                let trimmedToken = token.trimmingCharacters(in: noiseChars)
                                if !trimmedToken.isEmpty {
                                    self.strippedLeadingNoise = true
                                    if let idx = token.firstIndex(where: { !noiseChars.contains($0.unicodeScalars.first!) }) {
                                        self.onTokenGenerated?(String(token[idx...]))
                                    } else {
                                        self.onTokenGenerated?(trimmedToken)
                                    }
                                }
                            } else {
                                self.onTokenGenerated?(token)
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
        }
    }
}
