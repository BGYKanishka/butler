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

    var onIntentConfirmed: ((String) -> Void)?
    var onTokenGenerated: ((String) -> Void)?
    var onResponseCompleted: (() -> Void)?
    var onResponseIgnored: (() -> Void)?

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
            let context = await self.contextManager.getRecentContext()
            let projectSummary = self.projectContextManager?.currentContext?.summary
            let prompt = self.promptBuilder.build(context: context, projectSummary: projectSummary, question: transcript, source: source)

            var buffer = ""
            var decisionMade = false
            var isIntentValid = false
            var strippedLeadingNoise = false

            do {
                try await self.llmEngine.generateStreaming(prompt: prompt) { [weak self] token in
                    guard let self = self else { return }

                    if !decisionMade {
                        buffer += token
                        let trimmedUpper = buffer.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

                        if trimmedUpper.hasPrefix("YES") {
                            decisionMade = true
                            isIntentValid = true
                            self.onIntentConfirmed?(transcript)

                            var remaining = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                            if remaining.uppercased().hasPrefix("YES|") {
                                remaining = String(remaining.dropFirst(4))
                            } else if remaining.uppercased().hasPrefix("YES") {
                                remaining = String(remaining.dropFirst(3))
                            }

                            remaining = remaining.trimmingCharacters(in: CharacterSet(charactersIn: " |:\n\t"))

                            if !remaining.isEmpty {
                                strippedLeadingNoise = true
                                self.onTokenGenerated?(remaining)
                            }
                        } else if trimmedUpper.hasPrefix("NO") {
                            decisionMade = true
                            isIntentValid = false
                            self.llmEngine.cancel()
                        } else if buffer.count > 20 {
                            // Model skipped YES/NO — assume it's answering directly.
                            decisionMade = true
                            isIntentValid = true
                            strippedLeadingNoise = true
                            self.onIntentConfirmed?(transcript)
                            self.onTokenGenerated?(buffer)
                        }
                    } else if isIntentValid {
                        if !strippedLeadingNoise {
                            let noiseChars = CharacterSet(charactersIn: " |:\n\t")
                            let trimmedToken = token.trimmingCharacters(in: noiseChars)
                            if !trimmedToken.isEmpty {
                                strippedLeadingNoise = true
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

                if isIntentValid {
                    self.onResponseCompleted?()
                } else {
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
