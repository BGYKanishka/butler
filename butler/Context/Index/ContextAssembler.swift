import Foundation

struct ContextAssembler {
    static func assemble(_ chunks: [ScoredChunk], budgetTokens: Int, multiProject: Bool) -> String {
        if chunks.isEmpty { return "" }
        
        var sortedChunks = chunks
        // Sort by priority (symbol/path hits first)
        sortedChunks.sort { a, b in
            let aHasExact = a.sources.contains(.symbol) || a.sources.contains(.path)
            let bHasExact = b.sources.contains(.symbol) || b.sources.contains(.path)
            if aHasExact && !bHasExact { return true }
            if !aHasExact && bHasExact { return false }
            return a.score > b.score
        }
        
        var assembled = ""
        var currentTokens = 0
        var seenHashes = Set<String>()
        
        for (i, sc) in sortedChunks.enumerated() {
            let chunk = sc.chunk
            if seenHashes.contains(chunk.contentHash) { continue }
            
            let pLabel = multiProject ? "[\(sc.projectLabel)] " : ""
            let qName = chunk.qualifiedName != nil ? " \(chunk.qualifiedName!)" : ""
            let header = "[\(i+1)] \(pLabel)\(chunk.relPath):\(chunk.startLine)-\(chunk.endLine)\(qName)\n"
            
            let lang = URL(fileURLWithPath: chunk.relPath).pathExtension
            
            let maxChunkTokens = budgetTokens / 2
            var contentStr = chunk.content
            
            // Very rough token clipping
            let estLines = max(1, contentStr.components(separatedBy: .newlines).count)
            let avgTokensPerLine = Double(chunk.tokenEstimate) / Double(estLines)
            
            if chunk.tokenEstimate > maxChunkTokens {
                let allowedLines = Int(Double(maxChunkTokens) / max(1.0, avgTokensPerLine))
                let lines = contentStr.components(separatedBy: .newlines)
                if allowedLines > 2 && lines.count > allowedLines {
                    contentStr = lines.prefix(allowedLines).joined(separator: "\n") + "\n// ... clipped"
                }
            }
            
            let chunkTokens = PromptBuilder.estimateTokens(contentStr)
            
            if currentTokens + chunkTokens + 50 > budgetTokens {
                break
            }
            
            let block = "\(header)```\(lang)\n\(contentStr)\n```\n\n"
            assembled += block
            currentTokens += PromptBuilder.estimateTokens(block)
            seenHashes.insert(chunk.contentHash)
        }
        
        return assembled.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
