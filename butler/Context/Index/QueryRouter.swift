import Foundation

struct QueryRouter: Sendable {
    
    static func route(text: String, recentTurns: [ConversationTurn], lexicon: SymbolLexicon) -> RoutedQuery {
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
        let shouldRetrieve = !smallTalk && (!symbolHits.isEmpty || !fileHits.isEmpty || hasProjectName || projectCue)
        
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
        
        var ftsTerms = words.filter { !ProjectScanner.stopWords.contains($0) }
        ftsTerms.append(contentsOf: symbolHits)
        ftsTerms.append(contentsOf: fileHits)
        ftsTerms = Array(Set(ftsTerms)).prefix(12).map { $0 }
        
        return RoutedQuery(intent: intent, shouldRetrieve: shouldRetrieve, symbolHits: Array(Set(symbolHits)), fileHits: Array(Set(fileHits)), ftsTerms: ftsTerms, text: text)
    }
}
