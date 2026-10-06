import Foundation

/// Maps spoken concepts ("RAG", "analyze", "whisper") onto fragments of the project's OWN symbol and
/// file names, so a vague question still finds the right code. Matching is done against the indexed
/// lexicon, so a keyword that does not exist in the project simply contributes nothing.
enum ConceptExpander {
    struct Concept {
        let triggers: Set<String>
        let keywords: [String]
    }

    static let table: [Concept] = [
        Concept(triggers: ["rag", "reg", "frag", "rack", "retrieval", "retrieve", "retriever", "retrives"],
                keywords: ["retriev", "contextassembl", "queryrouter", "codechunk"]),
        Concept(triggers: ["analyze", "analyse", "analysis", "analyzer", "analyzing", "scanner"],
                keywords: ["analyz", "scanner", "contextmanager"]),
        Concept(triggers: ["whisper", "transcribe", "transcription", "transcript", "speech", "stt"],
                keywords: ["whisper", "transcri"]),
        Concept(triggers: ["vad", "voice", "silence"],
                keywords: ["voiceactivity", "audiosession"]),
        Concept(triggers: ["kv", "cache", "memory"],
                keywords: ["savestate", "loadstate", "memory"]),
        Concept(triggers: ["prompt", "prompting"],
                keywords: ["promptbuilder", "responsegenerator"]),
        Concept(triggers: ["index", "indexing", "sqlite", "fts"],
                keywords: ["indexcoordinator", "sqlite", "indexschema"]),
    ]

    static func keywords(forWords words: [String]) -> [String] {
        let set = Set(words)
        var out = [String]()
        for concept in table where !concept.triggers.isDisjoint(with: set) {
            out.append(contentsOf: concept.keywords)
        }
        return out
    }
}

struct QueryRouter: Sendable {

    /// Words that signal "continue the previous topic" rather than a self-contained question.
    private static let followUpCues: Set<String> = [
        "more", "explain", "elaborate", "detail", "details", "further", "again", "that", "it", "this",
        "those", "them", "previous", "same", "deeper", "continue"
    ]

    static func route(text originalText: String, recentTurns: [ConversationTurn], lexicon: SymbolLexicon) -> RoutedQuery {
        // A short follow-up ("Can we explain it more?") has no topic of its own. Borrow the previous
        // spoken question so retrieval looks for the same thing instead of matching random words.
        var text = originalText
        let rawFollowWords = originalText.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if rawFollowWords.count <= 8, !Set(rawFollowWords).isDisjoint(with: followUpCues),
           let previous = recentTurns.last(where: { $0.source != .assistant && $0.text != originalText }) {
            text = previous.text + " " + originalText
        }

        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let normText = words.joined(separator: " ")
        
        var symbolHits = [String]()
        var fileHits = [String]()
        
        let maxNgram = 4
        let wordCount = words.count
        for n in (1...maxNgram).reversed() {
            guard wordCount >= n else { continue }
            for i in 0...(wordCount - n) {
                let ngram = words[i..<(i+n)].joined(separator: " ")
                let norm = TermFormatter.normalized(ngram)
                if lexicon.symbolsByNorm[norm] != nil { symbolHits.append(norm) }
                if lexicon.filesByNorm[norm] != nil { fileHits.append(norm) }
            }
        }
        
        // Also add exact matches for CamelCase/snake_case/paths if they exist
        let rawWords = text.components(separatedBy: .whitespacesAndNewlines)
        for w in rawWords {
            let clean = w.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "_.")))
            let norm = TermFormatter.normalized(clean)
            if lexicon.symbolsByNorm[norm] != nil { symbolHits.append(norm) }
            if lexicon.filesByNorm[norm] != nil { fileHits.append(norm) }
        }
        
        // Concept expansion: "rag system" -> HybridProjectRetriever, ContextAssembler, QueryRouter, ...
        for keyword in ConceptExpander.keywords(forWords: words) {
            let symbolMatches = lexicon.symbolsByNorm.keys.filter { $0.contains(keyword) }.sorted { $0.count < $1.count }.prefix(4)
            symbolHits.append(contentsOf: symbolMatches)
            let fileMatches = lexicon.filesByNorm.keys.filter { $0.contains(keyword) }.sorted { $0.count < $1.count }.prefix(4)
            fileHits.append(contentsOf: fileMatches)
        }

        let pronouns: Set<String> = ["it", "that", "this", "those", "them"]
        if symbolHits.isEmpty && !Set(words).isDisjoint(with: pronouns) {
            for turn in recentTurns.suffix(2) {
                let tWords = turn.text.components(separatedBy: .whitespacesAndNewlines)
                for w in tWords {
                    let clean = w.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "_.")))
                    let norm = TermFormatter.normalized(clean)
                    if lexicon.symbolsByNorm[norm] != nil, symbolHits.count < 2 {
                        symbolHits.append(norm)
                    }
                }
            }
        }
        
        let projectCues = ["your project", "the project", "this project", "your code", "the codebase", "architecture", "how did you", "how do you", "how does", "where is", "where do", "which file", "implement", "designed", "why did you", "class", "function", "module", "pipeline", "component"]
        let hasCue = projectCues.contains { normText.contains($0) }
        let hasProjectName = lexicon.projectNames.contains { normText.contains($0) }
        let projectCue = hasCue && (!symbolHits.isEmpty || !fileHits.isEmpty || hasProjectName || normText.contains("your project") || normText.contains("the project") || normText.contains("your code"))
        
        let smallTalk = (words.count < 4 && symbolHits.isEmpty && fileHits.isEmpty) || words.isEmpty

        let hasGeneralCue = words.count > 3

        let shouldRetrieve = !smallTalk && (!symbolHits.isEmpty || !fileHits.isEmpty || hasProjectName || projectCue || hasGeneralCue)
        
        let intent: QueryIntent
        if (!symbolHits.isEmpty || !fileHits.isEmpty) && (normText.contains("where") || normText.contains("which file") || normText.contains("show")) {
            intent = .symbolLookup
        } else if !fileHits.isEmpty && symbolHits.isEmpty {
            intent = .fileLookup
        } else if normText.contains("architecture") || normText.contains("overview") || normText.contains("structure") || normText.contains("design") || normText.contains("flow") || normText.contains("pipeline") || normText.contains("components") {
            intent = .architecture
        } else if normText.contains("how") || normText.contains("implement") || normText.contains("work") {
            intent = .implementation
        } else {
            intent = .general
        }
        
        // Most specific terms first (resolved symbols/files), then plain words, de-duplicated in order.
        // `Array(Set(...)).prefix(12)` used to keep a RANDOM 12 of them.
        var ftsTerms = symbolHits + fileHits + words.filter { !ProjectScanner.stopWords.contains($0) }
        var seenTerms = Set<String>()
        ftsTerms = ftsTerms.filter { seenTerms.insert($0).inserted }.prefix(12).map { $0 }
        
        return RoutedQuery(intent: intent, shouldRetrieve: shouldRetrieve, symbolHits: Array(Set(symbolHits)), fileHits: Array(Set(fileHits)), ftsTerms: ftsTerms, text: originalText)
    }
}
