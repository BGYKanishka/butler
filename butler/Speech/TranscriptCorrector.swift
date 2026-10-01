import Foundation

/// Repairs the speech-to-text mistakes that silently break retrieval and answers.
///
/// Real example from a session log: the speaker said "RAG system" and Whisper produced
/// "regsystem", "frag system", "reg system" and "Rack System". The retriever then searched for
/// those literal words and returned unrelated llama.cpp code. Whisper's `initial_prompt` helps but is
/// not reliable for short acronyms, so common mishearings are fixed after transcription.
///
/// Rules are deliberately conservative: each one is an explicit pattern, and project-specific rules
/// only fire when the analysed project actually contains the concept (see `requiresMarker`).
final class TranscriptCorrector: @unchecked Sendable {
    static let shared = TranscriptCorrector()

    private struct Rule {
        let regex: NSRegularExpression
        let template: String
        /// Lower-case substring that must occur in the project vocabulary for the rule to apply.
        /// `nil` = always active (general technical vocabulary).
        let requiresMarker: String?
    }

    private let lock = NSLock()
    private var vocabularyBlob = ""
    private let rules: [Rule]

    init() {
        func rule(_ pattern: String, _ template: String, marker: String? = nil) -> Rule? {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
            return Rule(regex: re, template: template, requiresMarker: marker)
        }
        let built: [Rule?] = [
            // "reg system", "frag system", "rack system", "regsystem" -> "RAG system"
            rule(#"\b(?:reg|rag|frag|rack|wrag)[ -]?(system|pipeline|engine|retrieval|index|database)\b"#, "RAG $1", marker: "retriev"),
            rule(#"\bk\.?\s?v\.?\s?(?:cash|cache|cached)\b"#, "KV cache"),
            rule(#"\b(?:guff|g guf|gee guff)\b"#, "GGUF"),
            rule(#"\bl+ama[ .\-]?(?:c ?p ?p|see plus plus)\b"#, "llama.cpp"),
            rule(#"\bwhisper[ .\-]?(?:c ?p ?p|see plus plus)\b"#, "whisper.cpp"),
            rule(#"\bsequel[ -]?(?:lite|light)\b"#, "SQLite"),
            rule(#"\bf[ .]{0,2}t[ .]{0,2}s[ .]{0,2}(?:5|five)\b"#, "FTS5"),
        ]
        self.rules = built.compactMap { $0 }
    }

    /// Called whenever the analysed project (and therefore the vocabulary) changes.
    func update(vocabulary terms: [String]) {
        let blob = terms.joined(separator: " ").lowercased()
        lock.lock(); defer { lock.unlock() }
        vocabularyBlob = blob
    }

    func correct(_ text: String) -> String {
        lock.lock()
        let blob = vocabularyBlob
        lock.unlock()

        var result = text
        for rule in rules {
            if let marker = rule.requiresMarker, !blob.contains(marker) { continue }
            let range = NSRange(location: 0, length: (result as NSString).length)
            result = rule.regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: rule.template)
        }
        return result
    }
}
