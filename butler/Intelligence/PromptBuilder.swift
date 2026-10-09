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
        You are Butler, an AI assistant for live conversations, acting like a sharp senior engineer next to the user.

        RULES:
        - [USER]=Microphone, [OTHER PARTY]=System audio. Answer [USER] directly. For [OTHER PARTY], write what the user should say out loud.
        - If just greeting/small talk, output: NO. Otherwise, answer.
        \(projectContextBlock)
        GROUNDING:
        - PROJECT CONTEXT/RELEVANT CODE is ground truth. Don't invent files/functions.
        - Describe what code does plainly, then reference files/functions.
        - Third-party code isn't project logic. State only facts about external tools. Unsure? Say "I lack context."
        - If not in context, prefix: "Not in project context, but generally:" and use general knowledge.
        - Silently correct speech-to-text typos (e.g., "frag system" -> RAG).

        FORMAT (strict):
        - Start every answer with exactly YES| (write nothing before it).
        - Standard: MUST answer using EXACTLY ONE short sentence (max 20 words), followed by 3-7 bullets ("- "). Max 20 words/bullet. **Bold** key terms.
        - STRICTLY NO paragraphs. Do NOT write blocks of text.
        - STRICTLY NO code snippets or diagrams unless EXPLICITLY asked.
        - Processes: Numbered list in execution order. Comparisons: "- **A:** ..." / "- **B:** ...".
        - Deep dive ("explain more"): Paragraphs and >7 bullets allowed. Group with **bold** headings.
        - No intros, conclusions, or apologies.

        EXAMPLE:
        [OTHER PARTY]: Cache consistency?
        YES|
        **Writes update the database first, then overwrite the cache key.**
        - **Write path:** commit to database, then set cache entry
        - **Read path:** hit returns immediately; miss reloads from database
        - **Safety net:** 60s TTL bounds staleness
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
        let qLower = question.lowercased()
        let isDiagramRequest = qLower.range(of: "\\b(diagram|flowchart|graph)\\b", options: .regularExpression) != nil
        let isCodeRequest = qLower.range(of: "\\b(sql|query|code|script)\\b", options: .regularExpression) != nil
        let isExplainRequest = qLower.range(of: "\\b(explain|deep dive|detail|details)\\b", options: .regularExpression) != nil
        
        let reminder: String
        if isDiagramRequest {
            reminder = "(Reply: YES| then output a Mermaid.js diagram in a ```mermaid code block. Do NOT wrap regular conversational text in code blocks.)"
        } else if isCodeRequest {
            reminder = "(Reply: YES| first. Then provide EXACTLY 1 short sentence and \"- \" bullets. THEN place the requested code or SQL query at the end within a fenced markdown block (e.g., ```go, ```sql). Do NOT wrap regular text in code blocks.)"
        } else if isExplainRequest {
            reminder = "(Reply: YES| then provide a detailed explanation. Paragraphs and multiple bullets are ALLOWED. Group details with **bold** headings. Do NOT output code or diagrams unless explicitly asked.)"
        } else {
            reminder = "(Reply: YES| then EXACTLY 1 short sentence, followed by \"- \" bullets. YOU MUST NOT WRITE PARAGRAPHS. YOU MUST NOT WRITE CODE SNIPPETS. KEEP IT SHORT.)"
        }
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
