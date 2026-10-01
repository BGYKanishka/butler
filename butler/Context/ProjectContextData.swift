import Foundation

struct ProjectContextData: Equatable, Codable {
    /// Ranked terms (best first). Project names always come first.
    var vocabulary: [String]
    /// Text injected into the LLM system prompt.
    var summary: String
    /// Human-facing names of the project.
    var projectNames: [String] = []
}

extension ProjectContextData {
    /// Builds the short text Whisper receives as `initial_prompt`.
    func makeWhisperPrompt(maxChars: Int = 480) -> String {
        var seen = Set<String>()
        var terms = [String]()

        func add(_ raw: String) {
            let spoken = TermFormatter.spoken(raw)
            let key = spoken.lowercased()
            guard !spoken.isEmpty, seen.insert(key).inserted else { return }
            terms.append(spoken)
        }
        let header: String
        if projectNames.isEmpty {
            header = "Technical interview."
        } else {
            header = "Technical interview about \(projectNames.prefix(3).map { TermFormatter.spoken($0) }.joined(separator: ", "))."
        }
        
        for name in projectNames.prefix(3) { seen.insert(TermFormatter.spoken(name).lowercased()) }
        for name in projectNames.dropFirst(3) { add(name) }
        for word in vocabulary { add(word) }

        var prompt = header + " Terms:"
        var included = 0
        for term in terms {
            let candidate = prompt + (included == 0 ? " " : ", ") + term
            if candidate.count + 1 > maxChars { break }
            prompt = candidate
            included += 1
        }
        return included == 0 ? header : prompt + "."
    }
}
