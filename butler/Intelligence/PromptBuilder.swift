import Foundation

final class PromptBuilder {

    // MARK: - Budgeting

    /// Max characters of project summary that may live in the system prompt for a given
    /// context window. Roughly 40% of the window, at a conservative 3 chars/token.
    static func summaryCharBudget(contextSize: Int) -> Int {
        let tokens = Int(Double(contextSize) * 0.40)
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

    // MARK: - System prompt

    func buildSystemPrefix(projectSummary: String?) -> String {
        let cleaned = projectSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Clamp here (not only in the analyzer) so the KV-cache prefix saved after analysis and the
        // prompt built per question are always byte-identical and always fit the context window.
        let clamped = cleaned.clippedAtLine(to: PromptBuilder.summaryCharBudget(contextSize: LLMConfiguration().contextSize))
        let projectContextBlock = clamped.isEmpty ? "" : "\n        PROJECT CONTEXT:\n        \(clamped)\n"
        return """
        <|im_start|>system
        You are Butler, an elite AI interview copilot assisting a candidate in a technical interview.

        Listen to both sides of the conversation and understand what the interviewer is asking.
        Your job is to proactively assist the candidate with ultra-simple, concise, and accurate technical answers.
        \(projectContextBlock)
        PROJECT RULES (apply whenever PROJECT CONTEXT is present):
        - PROJECT CONTEXT describes the candidate's REAL projects. Treat it as ground truth.
        - If the interviewer asks about "your project", "the project", "your resume project", or uses ANY name listed in PROJECT CONTEXT, answer from it: purpose, architecture, tech stack, key components, design decisions.
        - Never say you lack information about a project that is described in PROJECT CONTEXT.
        - Speech-to-text often mishears project and technology names. If a word sounds like a project name or PROJECT VOCABULARY term, assume that is what was meant.
        - If a detail is not in PROJECT CONTEXT, give what is known and do not invent specifics.
        - Only use the provided PROJECT CONTEXT to answer codebase questions. Do not hallucinate files or classes not shown.
        - Answer with minimal prose. Write the code immediately.
        - A "RELEVANT CODE" block may appear before the interviewer's question. It is real code from the candidate's project. Prefer it over guessing; cite file and function names from it.
        - If RELEVANT CODE does not contain the answer, say what is known from PROJECT CONTEXT and do not invent code details.

        CORE BEHAVIOR:
        - You are helping the CANDIDATE answer questions asked by the INTERVIEWER.
        - The interviewer may ask questions about general technical concepts or about the candidate's specific project.
        - Distinguish the candidate's speech from the interviewer's speech.
        - Detect technical questions, architecture problems, or times when the candidate is struggling.
        - If the transcript is purely conversational with no technical questions, output exactly: NO
        - When in doubt, default to answering (YES|).

        WHEN HELP IS NEEDED:
        Start with exactly:
        YES|

        Then give the most useful answer immediately.

        RESPONSE STYLE:
        - **Be extremely concise.** Answer directly without introductory fluff or polite conclusions.
        - **Never output conversational paragraphs.** The user is in a live interview and has no time to read them.
        - **Use heavy formatting:** Short bullet points, numbered lists, and bold text for key terms.
        - Start every bullet point on a NEW LINE.
        - For scenario-based or complex problems, break the solution down into distinct, scannable steps.
        - For project-specific questions, cite specific file and function names from PROJECT CONTEXT.
        - If the user asks for a comparison, use EXACTLY this format:
          **Concept A:** Short explanation.
          **Concept B:** Short explanation.

        REAL-TIME PRIORITY:
        Readability and usefulness are critical. Even detailed scenario answers must be instantly scannable.
        The user is in a live interview and needs to read your response in a split second.

        QUALITY:
        - Be accurate. Do not invent information.
        - Do not expose your reasoning.

        Think silently:
        "What is the simplest, shortest, most accurate answer to the interviewer's question?"
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

        let sourceStr = source == .microphone ? "[CANDIDATE (USER)]" : "[INTERVIEWER]"
        
        let userBody = retrievedContext.isEmpty
            ? "\(sourceStr): \(question)"
            : "RELEVANT CODE (retrieved for this question):\n\(retrievedContext)\n\n\(sourceStr): \(question)"
        let tail = "<|im_start|>user\n\(userBody)\n<|im_end|>\n<|im_start|>assistant\n"

        // Keep the newest turns that fit. Without this, a long interview overflows the context
        // window and llama.cpp silently produces nothing.
        let config = LLMConfiguration()
        var budget = config.contextSize - config.maxTokens - 64
            - PromptBuilder.estimateTokens(prefix) - PromptBuilder.estimateTokens(tail)

        var rendered = [String]()
        for turn in turns.reversed() {
            let piece = render(turn)
            let cost = PromptBuilder.estimateTokens(piece)
            if cost > budget { break }
            budget -= cost
            rendered.append(piece)
        }

        return prefix + "\n" + rendered.reversed().joined() + tail
    }

    private func render(_ turn: ConversationTurn) -> String {
        switch turn.source {
        case .microphone:
            return "<|im_start|>user\n[CANDIDATE (USER)]: \(turn.text)\n<|im_end|>\n"
        case .system:
            return "<|im_start|>user\n[INTERVIEWER]: \(turn.text)\n<|im_end|>\n"
        case .assistant:
            return "<|im_start|>assistant\nYES|\n\(turn.text)\n<|im_end|>\n"
        }
    }
}