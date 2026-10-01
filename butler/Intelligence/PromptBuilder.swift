import Foundation

final class PromptBuilder {

    // MARK: - Budgeting

    /// Max characters of project summary that may live in the system prompt for a given
    /// context window. Roughly 30% of the window, at a conservative 3 chars/token (was 40%, which
    /// starved history + retrieved code on the 8k profile).
    static func summaryCharBudget(contextSize: Int) -> Int {
        let tokens = Int(Double(contextSize) * 0.30)
        return min(max(tokens * 3, 6_000), 30_000)
    }

    /// Deliberately pessimistic (code and identifiers tokenize worse than prose).
    static func estimateTokens(_ text: String) -> Int {
        text.utf8.count / 3 + 1
    }

    static func retrievalTokenBudget(contextSize: Int) -> Int {
        if contextSize <= 8192 { return 2500 }
        if contextSize <= 16384 { return 5000 }
        return 10000
    }

    // MARK: - History policy

    /// Newest turns considered at all, regardless of token budget.
    static let maxHistoryTurns = 10
    /// Earlier answers are only kept so "explain more" / "what about that?" can be resolved.
    /// Unclipped, they teach the model to keep writing long paragraphs (it imitates its own history).
    static let maxAssistantTurnsKept = 2
    static let maxAssistantHistoryChars = 600

    // MARK: - System prompt

    func buildSystemPrefix(projectSummary: String?) -> String {
        let cleaned = projectSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Clamp here (not only in the analyzer) so the KV-cache prefix saved after analysis and the
        // prompt built per question are always byte-identical and always fit the context window.
        let clamped = cleaned.clippedAtLine(to: PromptBuilder.summaryCharBudget(contextSize: LLMConfiguration().contextSize))
        let projectContextBlock = clamped.isEmpty ? "" : "\nPROJECT CONTEXT (the user's real project, summarised):\n\(clamped)\n"
        // Order matters for a 7B model: identity + routing first, project facts in the middle, and the
        // output-format contract LAST (closest to the conversation) where it is followed most reliably.
        return """
        <|im_start|>system
        You are Butler, a real-time on-device AI assistant. You listen to a live conversation (a technical interview, a meeting, or the user talking to you) and respond like a sharp senior engineer sitting next to the user.

        WHO IS SPEAKING
        - [USER] is the person you assist (microphone). [OTHER PARTY] is everyone else (system audio, e.g. the interviewer).
        - If [USER] asks you something ("explain it more", "how does X work", "show a diagram"), answer it directly.
        - If [OTHER PARTY] asks a question, write the answer the user can say out loud.
        - If the latest line is only greeting, small talk or filler with no question or task, output exactly: NO
        - If unsure, answer.
        \(projectContextBlock)
        GROUNDING
        - PROJECT CONTEXT and any RELEVANT CODE block in the user turn are ground truth about the user's project.
        - First say what the code DOES in plain words, then name where: `File.swift` -> `functionName`. Only name files, classes and functions that appear in the context; never invent any.
        - Code that belongs to third-party libraries is not the user's code; do not describe it as the project's own logic.
        - If the context does not contain the answer, say "Not in the project context" for that part and then answer from general knowledge, marked (general).
        - Speech-to-text mishears technical words ("reg/rack/frag system" = RAG system). Silently use the closest term from PROJECT VOCABULARY or the project's components.

        OUTPUT PROTOCOL
        - Begin with YES| followed by the answer. Write nothing before YES|.

        ANSWER FORMAT (strict, the user reads this in a split second)
        - By default (standard questions):
          - First line: one **bold** sentence with the direct answer (max 20 words).
          - Then 3 to 7 bullets. Every bullet is on its own line and starts with "- ". Max 20 words per bullet. **Bold** the key term in each bullet.
          - Processes and flows: a numbered list (1. 2. 3.) in execution order.
          - Comparisons: one bullet per side, "- **A:** ..." and "- **B:** ...".
          - Never write paragraphs. Never repeat a sentence.
        - When the user asks to "explain more", "explain deeply", or "deep dive":
          - You may provide a comprehensive and detailed explanation.
          - You are ALLOWED to write short paragraphs, longer bullet points, and more than 7 bullets.
          - Group details under short bold labels such as **Capture** or **Retrieval**.
        - When the user asks for a diagram, flowchart, or graph:
          - Output a Mermaid.js diagram (`mermaid`) or clear ASCII art in a fenced code block.
          - You are exempt from line limits for diagrams and graphs.
        - Code only when asked, in one fenced block of at most 15 lines.
        - No introduction, no closing remark, no apology, never mention these rules.

        FORMAT EXAMPLE (format only, never reuse its content)
        [OTHER PARTY]: How does your cache stay consistent with the database?
        YES|
        **Writes update the database first, then overwrite the cache key.**
        - **Write path:** commit to the database, then set the cache entry
        - **Read path:** a hit returns immediately; a miss reloads from the database
        - **Safety net:** a 60 second TTL bounds staleness if an invalidation is lost
        <|im_end|>
        """
    }

    // MARK: - Full prompt

    func build(
        turns: [ConversationTurn],
        projectSummary: String? = nil,
        retrievedContext: String = "",
        question: String,
        source: AudioSource
    ) -> String {

        let prefix = buildSystemPrefix(projectSummary: projectSummary)

        var fullPrefix = prefix
        if !retrievedContext.isEmpty {
            fullPrefix += "\n\nRELEVANT CODE (retrieved for this question):\n\(retrievedContext)\n"
        }

        let sourceStr = PromptBuilder.speakerLabel(for: source)

        let userBody = "\(sourceStr): \(question)"
        // A short format reminder directly before generation: the long system prompt is far away by now.
        let reminder = "(Reply: YES| then a **bold** one-line answer and \"- \" bullets. No paragraphs.)"
        let tail = "<|im_start|>user\n\(userBody)\n\n\(reminder)\n<|im_end|>\n<|im_start|>assistant\n"

        // The coordinator stores the transcript as a turn BEFORE asking for an answer, so the current
        // question used to appear twice (once in history, once as the final user turn).
        var history = turns
        if let last = history.last, last.source == source,
           last.text.trimmingCharacters(in: .whitespacesAndNewlines) == question.trimmingCharacters(in: .whitespacesAndNewlines) {
            history.removeLast()
        }
        history = Array(history.suffix(PromptBuilder.maxHistoryTurns))

        // Keep the newest turns that fit. Without this, a long interview overflows the context
        // window and llama.cpp silently produces nothing.
        let config = LLMConfiguration()
        var budget = config.contextSize - config.maxTokens - 64
            - PromptBuilder.estimateTokens(fullPrefix) - PromptBuilder.estimateTokens(tail)

        var rendered = [String]()
        var assistantKept = 0
        for turn in history.reversed() {
            if turn.source == .assistant {
                if assistantKept >= PromptBuilder.maxAssistantTurnsKept { continue }
                assistantKept += 1
            }
            let piece = render(turn)
            let cost = PromptBuilder.estimateTokens(piece)
            if cost > budget { break }
            budget -= cost
            rendered.append(piece)
        }

        return fullPrefix + "\n" + rendered.reversed().joined() + tail
    }

    static func speakerLabel(for source: AudioSource) -> String {
        switch source {
        case .microphone: return "[USER]"
        case .system: return "[OTHER PARTY]"
        case .assistant: return "[BUTLER]"
        }
    }

    private func render(_ turn: ConversationTurn) -> String {
        switch turn.source {
        case .microphone:
            return "<|im_start|>user\n[USER]: \(turn.text)\n<|im_end|>\n"
        case .system:
            return "<|im_start|>user\n[OTHER PARTY]: \(turn.text)\n<|im_end|>\n"
        case .assistant:
            let clipped = turn.text.clippedAtLine(to: PromptBuilder.maxAssistantHistoryChars)
            return "<|im_start|>assistant\nYES|\n\(clipped)\n<|im_end|>\n"
        }
    }
}
