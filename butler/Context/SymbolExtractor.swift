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
}
