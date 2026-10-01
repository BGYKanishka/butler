import Foundation

enum SymbolExtractor {

    private static func re(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let goRegexes = [
        re(#"^type\s+([A-Za-z_]\w*)\s+(?:struct|interface)"#),
        re(#"^func\s+(?:\([^)]*\)\s*)?([A-Z]\w*)"#)
    ]
    private static let swiftRegexes = [
        re(#"^\s*(?:@\w+\s+)*(?:(?:public|internal|private|fileprivate|open|final)\s+)*(?:class|struct|enum|actor|protocol)\s+([A-Za-z_]\w*)"#)
    ]
    private static let jsRegexes = [
        re(#"^\s*(?:export\s+(?:default\s+)?)?(?:async\s+)?(?:function\*?|class|interface|enum)\s+([A-Za-z_$][\w$]*)"#),
        re(#"^\s*export\s+(?:default\s+)?(?:const|let|type)\s+([A-Za-z_$][\w$]*)"#)
    ]
    private static let pyRegexes = [
        re(#"^(?:async\s+)?(?:def|class)\s+([A-Za-z]\w*)"#)
    ]
    private static let rustRegexes = [
        re(#"^\s*pub(?:\([^)]*\))?\s+(?:async\s+)?(?:fn|struct|enum|trait)\s+([A-Za-z_]\w*)"#)
    ]
    private static let jvmRegexes = [
        re(#"^\s*(?:(?:public|private|protected|internal|abstract|final|open|data|sealed|static)\s+)*(?:class|interface|enum|object|record)\s+([A-Za-z_]\w*)"#)
    ]
    private static let cRegexes = [
        re(#"@(?:interface|implementation)\s+([A-Za-z_]\w*)"#),
        re(#"^\s*(?:class|struct)\s+([A-Za-z_]\w*)\s*(?::|\{)"#)
    ]

    private static func regexes(for ext: String) -> [NSRegularExpression?] {
        switch ext {
        case "go": return goRegexes
        case "swift": return swiftRegexes
        case "js", "jsx", "ts", "tsx", "vue", "svelte": return jsRegexes
        case "py": return pyRegexes
        case "rs": return rustRegexes
        case "java", "kt", "cs", "scala": return jvmRegexes
        case "c", "cpp", "cc", "h", "hpp", "m", "mm": return cRegexes
        default: return []
        }
    }

    static func symbols(in text: String, ext: String, limit: Int = 10) -> [String] {
        let ns = NSString(string: text.count > 120_000 ? String(text.prefix(120_000)) : text)
        let range = NSRange(location: 0, length: ns.length)
        var found = [(Int, String)]()
        for case let regex? in regexes(for: ext) {
            regex.enumerateMatches(in: ns as String, options: [], range: range) { m, _, _ in
                guard let m = m, m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return }
                let name = ns.substring(with: m.range(at: 1))
                if name.hasPrefix("_") { return }
                found.append((m.range.location, name))
            }
        }
        var seen = Set<String>()
        return found.sorted { $0.0 < $1.0 }.map { $0.1 }.filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }

    // --- Declarations ---

    struct Declaration: Sendable, Equatable {
        let name: String
        let kind: String
        let line: Int
        let indent: Int
    }

    private struct DeclPattern {
        let re: NSRegularExpression
        let kindIndex: Int
        let nameIndex: Int
        let fixedKind: String?
    }

    private static func declRe(_ pattern: String, kind: Int, name: Int, fixed: String? = nil) -> DeclPattern? {
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return nil }
        return DeclPattern(re: r, kindIndex: kind, nameIndex: name, fixedKind: fixed)
    }

    private static let declRegexesDict: [String: [DeclPattern]] = {
        var d = [String: [DeclPattern]]()
        let swift = [
            declRe(#"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|open|final|static|class|override|mutating|nonisolated|@MainActor)\s+)*(class|struct|enum|actor|protocol)\s+([A-Za-z_]\w*)"#, kind: 1, name: 2),
            declRe(#"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|open|final|static|class|override|mutating|nonisolated|@MainActor)\s+)*func\s+([A-Za-z_]\w*)"#, kind: 0, name: 1, fixed: "func"),
            declRe(#"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|open|final|static|class|override|mutating|nonisolated|@MainActor)\s+)*(init)\b"#, kind: 0, name: 1, fixed: "init"),
            declRe(#"^\s*(extension)\s+([A-Za-z_]\w*)"#, kind: 1, name: 2)
        ].compactMap { $0 }
        
        let go = [
            declRe(#"^type\s+([A-Za-z_]\w*)\s+(struct|interface)"#, kind: 2, name: 1),
            declRe(#"^func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)"#, kind: 0, name: 1, fixed: "func")
        ].compactMap { $0 }
        
        let js = [
            declRe(#"^\s*(?:export\s+(?:default\s+)?)?(?:async\s+)?(function\*?|class|interface|enum)\s+([A-Za-z_$][\w$]*)"#, kind: 1, name: 2),
            declRe(#"^\s*(?:export\s+(?:default\s+)?)?(?:const|let)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>"#, kind: 0, name: 1, fixed: "function"),
            declRe(#"^\s{2,}(?:async\s+)?([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{"#, kind: 0, name: 1, fixed: "method")
        ].compactMap { $0 }
        
        let py = [
            declRe(#"^\s*(?:async\s+)?(def|class)\s+([A-Za-z_]\w*)"#, kind: 1, name: 2)
        ].compactMap { $0 }
        
        let rust = [
            declRe(#"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(fn|struct|enum|trait)\s+([A-Za-z_]\w*)"#, kind: 1, name: 2),
            declRe(#"^\s*(impl)\s+(?:<[^>]*>\s*)?([A-Za-z_]\w*)"#, kind: 1, name: 2)
        ].compactMap { $0 }
        
        let jvm = [
            declRe(#"^\s*(?:(?:public|private|protected|internal|abstract|final|open|data|sealed|static)\s+)*(class|interface|enum|object|record)\s+([A-Za-z_]\w*)"#, kind: 1, name: 2),
            declRe(#"^\s*(?:(?:public|private|protected|internal|abstract|final|open|static|override)\s+)*[\w<>\[\]?.*]+\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*(?:\{|throws)"#, kind: 0, name: 1, fixed: "method"),
            declRe(#"^\s*(?:(?:public|private|protected|internal|abstract|final|open|static|override)\s+)*fun\s+([A-Za-z_]\w*)"#, kind: 0, name: 1, fixed: "fun")
        ].compactMap { $0 }

        let c = [
            declRe(#"^\s*@(interface|implementation)\s+([A-Za-z_]\w*)"#, kind: 1, name: 2),
            declRe(#"^\s*(class|struct)\s+([A-Za-z_]\w*)\s*(?::|\{)"#, kind: 1, name: 2),
            declRe(#"^\s*[-+]\s*\([^)]+\)\s*([A-Za-z_]\w*)"#, kind: 0, name: 1, fixed: "method"),
            declRe(#"^\w[\w\s\*&:<>]+\s+([A-Za-z_]\w*)\s*\([^;{]*\)\s*\{"#, kind: 0, name: 1, fixed: "func")
        ].compactMap { $0 }

        d["swift"] = swift
        d["go"] = go
        d["js"] = js; d["jsx"] = js; d["ts"] = js; d["tsx"] = js; d["vue"] = js; d["svelte"] = js
        d["py"] = py
        d["rs"] = rust
        d["java"] = jvm; d["kt"] = jvm; d["cs"] = jvm; d["scala"] = jvm
        d["c"] = c; d["cpp"] = c; d["cc"] = c; d["h"] = c; d["hpp"] = c; d["m"] = c; d["mm"] = c
        return d
    }()

    static func declarations(in text: String, ext: String) -> [Declaration] {
        guard let patterns = declRegexesDict[ext] else { return [] }
        let ns = NSString(string: text)
        let len = ns.length
        
        var lineStarts = [Int]()
        lineStarts.append(0)
        for i in 0..<len {
            if ns.character(at: i) == 10 { lineStarts.append(i + 1) }
        }
        
        func lineFor(offset: Int) -> Int {
            var low = 0
            var high = lineStarts.count - 1
            while low <= high {
                let mid = (low + high) / 2
                if lineStarts[mid] <= offset {
                    if mid == lineStarts.count - 1 || lineStarts[mid + 1] > offset { return mid + 1 }
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            return 1
        }
        
        func countIndent(for offset: Int) -> Int {
            let lineStart = lineStarts[lineFor(offset: offset) - 1]
            var ind = 0
            var j = lineStart
            while j < len {
                let c = ns.character(at: j)
                if c == 32 { ind += 1 } else if c == 9 { ind += 4 } else { break }
                j += 1
            }
            return ind
        }

        var results = [Declaration]()
        for p in patterns {
            p.re.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: len)) { m, _, _ in
                guard let m = m else { return }
                var kind = p.fixedKind ?? ""
                if kind.isEmpty, p.kindIndex > 0, m.range(at: p.kindIndex).location != NSNotFound {
                    kind = ns.substring(with: m.range(at: p.kindIndex))
                }
                guard p.nameIndex > 0, m.range(at: p.nameIndex).location != NSNotFound else { return }
                let name = ns.substring(with: m.range(at: p.nameIndex))
                
                let offset = m.range.location
                let line = lineFor(offset: offset)
                let indent = countIndent(for: offset)
                
                results.append(Declaration(name: name, kind: kind, line: line, indent: indent))
            }
        }
        
        return results.sorted { ($0.line, $0.indent) < ($1.line, $1.indent) }
    }
}
