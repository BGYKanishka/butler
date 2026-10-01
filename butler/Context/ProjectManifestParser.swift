import Foundation

enum ProjectManifestParser {
    static func goModuleName(_ text: String) -> String? {
        guard let path = ProjectScanner.firstMatch(#"(?m)^module\s+(\S+)"#, in: text) else { return nil }
        return path.split(separator: "/").last.map(String.init)
    }

    static func goDependencies(_ text: String) -> [String] {
        var out = [String]()
        for line in text.components(separatedBy: "\n") where !line.contains("// indirect") {
            if let path = ProjectScanner.firstMatch(#"^\s*(?:require\s+)?([A-Za-z0-9_.\-]+(?:/[A-Za-z0-9_.\-]+)+)\s+v[0-9]"#, in: line),
               let last = path.split(separator: "/").last {
                out.append(String(last))
            }
        }
        return out
    }

    static func packageJSONDependencies(_ url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let deps = obj["dependencies"] as? [String: Any] else { return [] }
        return deps.keys.sorted().map { $0.split(separator: "/").last.map(String.init) ?? $0 }
    }

    static func cargoDependencies(_ text: String) -> [String] {
        var out = [String](); var inDeps = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { inDeps = (t == "[dependencies]"); continue }
            if inDeps, let n = ProjectScanner.firstMatch(#"^([A-Za-z0-9_\-]+)\s*="#, in: t) { out.append(n) }
        }
        return out
    }

    static func requirementsDependencies(_ text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { ProjectScanner.firstMatch(#"^([A-Za-z][A-Za-z0-9_.\-]+)"#, in: $0) }
    }

    static func jsonString(_ url: URL, key: String) -> String? {
        guard let data = try? Data(contentsOf: url),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return obj[key] as? String
    }
}
