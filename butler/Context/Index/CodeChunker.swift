import Foundation

struct CodeChunker: Sendable {
    static let version = 1
    var targetChars = 900
    var softMaxChars = 1400
    var hardMaxChars = 1800
    
    func chunk(relPath: String, ext: String, text: String) -> (symbols: [ChunkedSymbol], chunks: [CodeChunk]) {
        let lines = text.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return ([], []) }
        
        let decls = SymbolExtractor.declarations(in: text, ext: ext)
        if decls.isEmpty || isMarkdownOrConfig(ext) {
            return ([], fallbackWindows(relPath: relPath, ext: ext, lines: lines))
        }
        
        // Find end lines
        var extendedDecls = [(decl: SymbolExtractor.Declaration, endLine: Int)]()
        for i in 0..<decls.count {
            let decl = decls[i]
            let nextSameOrLower = decls.dropFirst(i + 1).first { $0.indent <= decl.indent }
            let maxEndLine = (nextSameOrLower?.line ?? (lines.count + 1)) - 1
            
            let endLine = findEndLine(lines: lines, startLine: decl.line, ext: ext, declIndent: decl.indent, maxEndLine: maxEndLine)
            extendedDecls.append((decl, min(endLine, maxEndLine)))
        }
        
        // Build symbols with parents
        var symbols = [ChunkedSymbol]()
        var declToSymbol = [Int: ChunkedSymbol]()
        
        for (i, ed) in extendedDecls.enumerated() {
            let decl = ed.decl
            // Find parent: the last decl before this one that encompasses this one
            var parentSymbol: ChunkedSymbol?
            for j in (0..<i).reversed() {
                let p = extendedDecls[j]
                if p.decl.line < decl.line && p.endLine >= ed.endLine {
                    parentSymbol = declToSymbol[j]
                    break
                }
            }
            
            let parentName = parentSymbol?.name
            let qualified = parentName.map { "\($0).\(decl.name)" } ?? decl.name
            
            let sym = ChunkedSymbol(
                name: decl.name,
                qualified: qualified,
                kind: decl.kind,
                parent: parentName,
                startLine: decl.line,
                endLine: ed.endLine
            )
            symbols.append(sym)
            declToSymbol[i] = sym
        }
        
        var chunks = [CodeChunk]()
        var index = 0
        
        func addChunk(sym: ChunkedSymbol?, startLine: Int, endLine: Int, isPreamble: Bool = false) {
            let s = max(1, startLine)
            let e = min(lines.count, max(s, endLine))
            guard s <= e else { return }
            
            let contentLines = Array(lines[(s-1)..<e])
            let content = contentLines.joined(separator: "\n")
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
            
            if content.count > hardMaxChars {
                let parts = splitLargeContent(contentLines: contentLines, startLine: s, sym: sym)
                for part in parts {
                    let hash = FileFingerprint.sha256(of: part.content)
                    chunks.append(CodeChunk(
                        id: 0, relPath: relPath, symbolName: sym?.name, qualifiedName: sym?.qualified,
                        kind: sym?.kind ?? "chunk", startLine: part.startLine, endLine: part.endLine,
                        content: part.content, contentHash: hash, tokenEstimate: part.content.count / 3 // Simple estimate
                    ))
                    index += 1
                }
            } else {
                let hash = FileFingerprint.sha256(of: content)
                chunks.append(CodeChunk(
                    id: 0, relPath: relPath, symbolName: sym?.name, qualifiedName: sym?.qualified,
                    kind: isPreamble ? "preamble" : (sym?.kind ?? "chunk"), startLine: s, endLine: e,
                    content: content, contentHash: hash, tokenEstimate: content.count / 3
                ))
                index += 1
            }
        }
        
        // File preamble
        let firstDeclLine = decls.first?.line ?? (lines.count + 1)
        if firstDeclLine > 1 {
            addChunk(sym: nil, startLine: 1, endLine: min(firstDeclLine - 1, 40), isPreamble: true)
        }
        
        // Chunk per leaf symbol or type header
        var i = 0
        while i < symbols.count {
            let sym = symbols[i]
            let isType = isTypeKind(sym.kind)
            
            var childCount = 0
            for j in (i+1)..<symbols.count {
                if symbols[j].parent == sym.name { childCount += 1 }
                else if symbols[j].startLine > sym.endLine { break }
            }
            
            if isType && childCount > 0 {
                let firstChildLine = symbols[i+1].startLine
                addChunk(sym: sym, startLine: sym.startLine, endLine: firstChildLine - 1)
            } else {
                addChunk(sym: sym, startLine: sym.startLine, endLine: sym.endLine)
            }
            i += 1
        }
        
        return (symbols, chunks)
    }
    
    private func findEndLine(lines: [String], startLine: Int, ext: String, declIndent: Int, maxEndLine: Int) -> Int {
        if ext == "py" {
            for i in startLine..<maxEndLine {
                let line = lines[i]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let ind = indent(of: line)
                if ind <= declIndent { return i }
            }
            return maxEndLine
        }
        
        // Brace languages
        var foundBrace = false
        var braceDepth = 0
        var state = 0 // 0: normal, 1: line comment, 2: block comment, 3: string, 4: char, 5: multiline string
        
        for i in (startLine - 1)..<maxEndLine {
            let line = lines[i]
            var j = line.startIndex
            let end = line.endIndex
            
            while j < end {
                let c = line[j]
                
                if state == 1 { break } // Line comment
                
                let nextIdx = line.index(after: j)
                let next = nextIdx < end ? line[nextIdx] : Character("\0")
                
                switch state {
                case 0:
                    if c == "/" && next == "/" { state = 1; break }
                    if c == "/" && next == "*" { state = 2; j = nextIdx; break }
                    if c == "\"" {
                        if ext == "swift" && line.dropFirst(j.utf16Offset(in: line)).hasPrefix("\"\"\"") {
                            state = 5; j = line.index(j, offsetBy: 2)
                        } else {
                            state = 3
                        }
                    }
                    if c == "'" { state = 4 }
                    if c == "{" {
                        foundBrace = true
                        braceDepth += 1
                    }
                    if c == "}" {
                        braceDepth -= 1
                        if foundBrace && braceDepth == 0 { return i + 1 }
                    }
                case 2:
                    if c == "*" && next == "/" { state = 0; j = nextIdx }
                case 3:
                    if c == "\\" { j = nextIdx }
                    else if c == "\"" { state = 0 }
                case 4:
                    if c == "\\" { j = nextIdx }
                    else if c == "'" { state = 0 }
                case 5:
                    if line.dropFirst(j.utf16Offset(in: line)).hasPrefix("\"\"\"") {
                        state = 0; j = line.index(j, offsetBy: 2)
                    }
                default: break
                }
                if state == 1 { break }
                if j < end {
                    j = line.index(after: j)
                }
            }
            if state == 1 { state = 0 } // Reset line comment
        }
        return maxEndLine
    }
    
    private func fallbackWindows(relPath: String, ext: String, lines: [String]) -> [CodeChunk] {
        var chunks = [CodeChunk]()
        let isMd = ext == "md"
        var currentBlock = [String]()
        var startLine = 1
        var currentTokens = 0
        
        for (i, line) in lines.enumerated() {
            let isBoundary = isMd ? line.hasPrefix("#") : line.trimmingCharacters(in: .whitespaces).isEmpty
            let lineTokens = max(1, line.count / 3)
            
            if isBoundary && currentTokens > targetChars / 3 {
                let content = currentBlock.joined(separator: "\n")
                chunks.append(CodeChunk(id: 0, relPath: relPath, symbolName: nil, qualifiedName: nil, kind: "text", startLine: startLine, endLine: i, content: content, contentHash: FileFingerprint.sha256(of: content), tokenEstimate: currentTokens))
                currentBlock = []
                startLine = i + 1
                currentTokens = 0
            }
            currentBlock.append(line)
            currentTokens += lineTokens
        }
        if !currentBlock.isEmpty {
            let content = currentBlock.joined(separator: "\n")
            chunks.append(CodeChunk(id: 0, relPath: relPath, symbolName: nil, qualifiedName: nil, kind: "text", startLine: startLine, endLine: lines.count, content: content, contentHash: FileFingerprint.sha256(of: content), tokenEstimate: currentTokens))
        }
        return chunks
    }
    
    private func splitLargeContent(contentLines: [String], startLine: Int, sym: ChunkedSymbol?) -> [(startLine: Int, endLine: Int, content: String)] {
        var parts = [(startLine: Int, endLine: Int, content: String)]()
        let sigLine = sym != nil ? contentLines.first! : ""
        
        var currentLines = [String]()
        var currentStart = startLine
        var partIndex = 1
        
        for (i, line) in contentLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isBlank = trimmed.isEmpty
            
            currentLines.append(line)
            let currentContent = currentLines.joined(separator: "\n")
            
            if currentContent.count >= softMaxChars && isBlank {
                var c = currentContent
                if sym != nil && partIndex > 1 { c = "\(sigLine)\n// (part \(partIndex)/n)\n" + c }
                parts.append((currentStart, startLine + i, c))
                currentLines = []
                currentStart = startLine + i + 1
                partIndex += 1
            }
        }
        
        if !currentLines.isEmpty {
            var c = currentLines.joined(separator: "\n")
            if sym != nil && partIndex > 1 {
                c = "\(sigLine)\n// (part \(partIndex)/n)\n" + c
                if let last = parts.last {
                    parts[parts.count - 1].content = last.content.replacingOccurrences(of: "/n)", with: "/\(partIndex))")
                }
                c = c.replacingOccurrences(of: "/n)", with: "/\(partIndex))")
            }
            parts.append((currentStart, startLine + contentLines.count - 1, c))
        }
        
        return parts
    }
    
    private func isMarkdownOrConfig(_ ext: String) -> Bool {
        return ["md", "yml", "yaml", "toml", "json", "txt"].contains(ext)
    }
    
    private func isTypeKind(_ kind: String) -> Bool {
        return ["class", "struct", "enum", "protocol", "actor", "interface", "trait"].contains(kind)
    }
    
    private func indent(of line: String) -> Int {
        var ind = 0
        for c in line {
            if c == " " { ind += 1 }
            else if c == "\t" { ind += 4 }
            else { break }
        }
        return ind
    }
}
