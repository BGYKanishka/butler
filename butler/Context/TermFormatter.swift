import Foundation

enum TermFormatter {
    static func spoken(_ term: String) -> String {
        let chars = Array(term)
        var out = ""
        var prev: Character? = nil
        for (i, c) in chars.enumerated() {
            if c == "_" || c == "-" || c == "." {
                if !out.hasSuffix(" ") { out += " " }
                prev = c
                continue
            }
            if c.isUppercase, let p = prev {
                if p.isLowercase || p.isNumber {
                    out += " "
                } else if p.isUppercase, i + 1 < chars.count, chars[i + 1].isLowercase {
                    out += " "
                }
            }
            out.append(c)
            prev = c
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { word -> String in
            guard let first = word.first else { return String(word) }
            if word.contains(where: { $0.isUppercase }) { return String(word) }
            return String(first).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
