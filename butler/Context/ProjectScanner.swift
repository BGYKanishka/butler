import Foundation

struct ScannedFile {
    let url: URL
    let path: String
    let name: String
    let ext: String
    let depth: Int
    let isTest: Bool
}

enum ProjectScanner {
    static let ignoredDirs: Set<String> = [
        "node_modules", "Pods", "build", ".build", ".git", "vendor", "dist", "target", "out", "bin",
        "__pycache__", ".next", "coverage", "Carthage", "DerivedData", "venv", ".venv",
        "site-packages", ".gradle", ".idea", "obj", ".cache", "tmp", ".svn"
    ]
    static let ignoredDirExtensions: Set<String> = ["xcodeproj", "xcworkspace", "xcassets", "framework", "app", "bundle"]

    static let sourceExts: Set<String> = [
        "swift", "js", "jsx", "ts", "tsx", "py", "go", "java", "kt", "rs", "cpp", "cc", "hpp",
        "h", "c", "mm", "m", "rb", "php", "cs", "scala", "dart", "vue", "svelte"
    ]
    static let structureExts: Set<String> = sourceExts.union(["md", "yml", "yaml", "toml", "sh", "proto", "sql", "gradle"])
    static let structureNames: Set<String> = ["Dockerfile", "Makefile", "go.mod", "package.json", "Cargo.toml", "Package.swift", "pyproject.toml", "requirements.txt"]

    static let stopWords: Set<String> = [
        "index", "main", "test", "tests", "spec", "config", "configs", "types", "type", "utils", "util",
        "utility", "helpers", "helper", "common", "constants", "readme", "license", "package", "version",
        "default", "string", "false", "true", "null", "none", "this", "that", "with", "from", "init",
        "setup", "build", "dist", "node", "http", "json", "yaml", "file", "files", "data", "model",
        "models", "view", "views", "app", "src", "lib", "cmd", "internal", "pkg", "docs", "assets",
        "public", "static", "components", "hooks", "handlers", "handler", "service", "services",
        "client", "server", "core", "base", "error", "errors", "logger", "main", "module", "scripts"
    ]

    static let maxFiles = 5000
    static let maxFileBytes = 200_000
    static let maxSourceFilesRead = 800

    static func analyze(root inputRoot: URL, budget: Int) -> ProjectContextData {
        let root = inputRoot.resolvingSymlinksInPath()
        let folderName = root.lastPathComponent
        let files = scanFiles(root: root)

        if files.isEmpty {
            let names = nameVariants(candidates: [folderName])
            return ProjectContextData(
                vocabulary: names,
                summary: "CANDIDATE'S PROJECT: \"\(names.first ?? folderName)\" (No readable files were found).",
                projectNames: names
            )
        }

        let readmeFile = files
            .filter { $0.url.lastPathComponent.lowercased().hasPrefix("readme") }
            .sorted { ($0.depth, $0.path) < ($1.depth, $1.path) }.first
        let readmeText = readmeFile.flatMap { readText($0.url) } ?? ""

        func manifests(_ name: String) -> [ScannedFile] {
            files.filter { $0.url.lastPathComponent == name }
                .sorted { ($0.depth, $0.path) < ($1.depth, $1.path) }
                .prefix(2).map { $0 }
        }
        
        let goMods = manifests("go.mod")
        let packageJSONs = manifests("package.json")
        let cargoTomls = manifests("Cargo.toml")
        let pyprojects = manifests("pyproject.toml")
        let requirements = manifests("requirements.txt")
        let projectYML = manifests("project.yml")

        var nameCandidates = [String]()
        if let title = readmeTitle(readmeText) { nameCandidates.append(title) }
        nameCandidates.append(folderName)
        if let mod = goMods.first.flatMap({ readText($0.url) }).flatMap(ProjectManifestParser.goModuleName) { nameCandidates.append(mod) }
        for pj in packageJSONs { if let n = ProjectManifestParser.jsonString(pj.url, key: "name") { nameCandidates.append(n) } }
        for ct in cargoTomls + pyprojects {
            if let t = readText(ct.url), let n = firstMatch(#"(?m)^\s*name\s*=\s*"([^"]+)""#, in: t) { nameCandidates.append(n) }
        }
        for y in projectYML {
            if let t = readText(y.url), let n = firstMatch(#"(?m)^name:\s*([A-Za-z0-9_\-. ]+)$"#, in: t) { nameCandidates.append(n.trimmingCharacters(in: .whitespaces)) }
        }
        let projectNames = nameVariants(candidates: nameCandidates)

        var stackCounts = [String: Int]()
        func bumpStack(_ s: String) { stackCounts[s, default: 0] += 1 }
        for f in files {
            switch f.ext {
            case "swift": bumpStack("Swift")
            case "mm", "m", "c", "cpp", "cc", "h", "hpp": bumpStack("C/C++/Obj-C")
            case "js": bumpStack("JavaScript")
            case "jsx": bumpStack("JavaScript"); bumpStack("React")
            case "ts": bumpStack("TypeScript")
            case "tsx": bumpStack("TypeScript"); bumpStack("React")
            case "py": bumpStack("Python")
            case "go": bumpStack("Go")
            case "java": bumpStack("Java")
            case "kt": bumpStack("Kotlin")
            case "rs": bumpStack("Rust")
            case "rb": bumpStack("Ruby")
            case "php": bumpStack("PHP")
            case "cs": bumpStack("C#")
            case "dart": bumpStack("Dart")
            case "vue": bumpStack("Vue")
            case "svelte": bumpStack("Svelte")
            default: break
            }
            switch f.url.lastPathComponent {
            case "package.json": bumpStack("Node.js")
            case "Podfile": bumpStack("CocoaPods")
            case "Cargo.toml": bumpStack("Rust")
            case "go.mod": bumpStack("Go")
            case "Dockerfile", "docker-compose.yml", "docker-compose.yaml": bumpStack("Docker")
            case "Package.swift": bumpStack("Swift Package Manager")
            case "pyproject.toml", "requirements.txt": bumpStack("Python")
            default: break
            }
        }
        let stack = stackCounts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { $0.key }

        var dependencies = [String]()
        for gm in goMods { if let t = readText(gm.url) { dependencies += ProjectManifestParser.goDependencies(t) } }
        for pj in packageJSONs { dependencies += ProjectManifestParser.packageJSONDependencies(pj.url) }
        for ct in cargoTomls { if let t = readText(ct.url) { dependencies += ProjectManifestParser.cargoDependencies(t) } }
        for rq in requirements { if let t = readText(rq.url) { dependencies += ProjectManifestParser.requirementsDependencies(t) } }
        dependencies = unique(dependencies).filter { $0.count >= 4 }

        var scores = [String: Int]()
        var display = [String: String]()
        func bump(_ term: String, _ by: Int) {
            let clean = term.trimmingCharacters(in: CharacterSet(charactersIn: " :.,;*`\"'"))
            guard isUsefulTerm(clean) else { return }
            let key = clean.lowercased()
            scores[key, default: 0] += by
            if display[key] == nil { display[key] = clean }
        }

        let sourceFiles = files.filter { sourceExts.contains($0.ext) && !$0.isTest }
        var symbolsByFile = [(path: String, symbols: [String])]()

        for (index, f) in sourceFiles.enumerated() {
            bump(f.name, 3)
            if index < maxSourceFilesRead, let text = readText(f.url) {
                let syms = SymbolExtractor.symbols(in: text, ext: f.ext)
                for s in syms { bump(s, 2) }
                if !syms.isEmpty { symbolsByFile.append((f.path, syms)) }
            }
        }
        
        var dirNames = Set<String>()
        for f in files {
            for dir in f.path.split(separator: "/").dropLast() { dirNames.insert(String(dir)) }
        }
        for dir in dirNames { bump(dir, 1) }
        for dep in dependencies { bump(dep, 4) }
        for term in readmeTerms(readmeText) { bump(term, 6) }

        var vocabulary = [String]()
        var seenVocab = Set<String>()
        for n in projectNames where seenVocab.insert(n.lowercased()).inserted { vocabulary.append(n) }
        let ranked = scores.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        for (key, _) in ranked where seenVocab.insert(key).inserted {
            vocabulary.append(display[key] ?? key)
            if vocabulary.count >= 150 { break }
        }

        let primary = projectNames.first ?? folderName
        var identity = "CANDIDATE'S PROJECT: \"\(primary)\" (folder: \(folderName))."
        let aliases = projectNames.dropFirst().filter { TermFormatter.normalized($0) != TermFormatter.normalized(primary) }
        if !aliases.isEmpty { identity += " Also referred to as: \(aliases.joined(separator: ", "))." }
        identity += "\nWhen the interviewer says any of these names (or a word that sounds like one), they mean this project."
        identity += "\nThe candidate's project is named '\(primary)' and relies on: \(stack.isEmpty ? "unknown technologies" : stack.joined(separator: ", "))."
        if !dependencies.isEmpty { identity += "\nKey dependencies: \(dependencies.prefix(15).joined(separator: ", "))." }
        if let desc = packageJSONs.first.flatMap({ ProjectManifestParser.jsonString($0.url, key: "description") }), !desc.isEmpty {
            identity += "\nDescription: \(desc)"
        }

        let vocabBlock = "\n\nPROJECT VOCABULARY (Use this to correct phonetic transcription errors):\n"
            + vocabulary.prefix(60).joined(separator: ", ").clippedAtLine(to: 900)

        let usable = max(budget - vocabBlock.count, 1200)
        var out = identity
        func remaining() -> Int { usable - out.count }
        func addSection(_ title: String, _ body: String, cap: Int) {
            guard !body.isEmpty else { return }
            let room = min(cap, remaining() - title.count - 4)
            guard room > 120 else { return }
            out += "\n\n\(title):\n" + body.clippedAtLine(to: room)
        }

        addSection("PROJECT README EXCERPT", cleanReadme(readmeText), cap: Int(Double(usable) * 0.30))
        addSection("PROJECT STRUCTURE (directory: files)", structureMap(files), cap: Int(Double(usable) * 0.20))
        addSection("KEY COMPONENTS (declarations per file)",
                   symbolsByFile.map { "\($0.path): \($0.symbols.joined(separator: ", "))" }.joined(separator: "\n"),
                   cap: Int(Double(usable) * 0.28))

        var config = ""
        if let m = (goMods + packageJSONs + cargoTomls + pyprojects + projectYML).first, let t = readText(m.url) {
            config = "\(m.path):\n" + String(t.prefix(900))
        }
        addSection("PROJECT CONFIG EXCERPT", config, cap: Int(Double(usable) * 0.06))

        var excerpts = ""
        let entryNames: Set<String> = ["main", "app", "index", "server", "daemon", "cli", "core"]
        let entryFiles = sourceFiles.sorted { a, b in
            let ea = entryNames.contains(a.name.lowercased()) ? 0 : 1
            let eb = entryNames.contains(b.name.lowercased()) ? 0 : 1
            return (ea, a.depth, a.path) < (eb, b.depth, b.path)
        }.prefix(6)
        
        for f in entryFiles {
            guard remaining() - excerpts.count > 500, let t = readText(f.url) else { continue }
            excerpts += "\n--- \(f.path) ---\n" + String(t.prefix(1200))
        }
        addSection("SOURCE CODE EXCERPTS", excerpts, cap: remaining())

        out += vocabBlock
        return ProjectContextData(vocabulary: vocabulary, summary: out, projectNames: projectNames)
    }

    static func isSecretLike(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix(".env") || lower.hasPrefix("id_rsa") || lower.hasPrefix("id_ed25519") || lower.hasPrefix("credentials") || lower.hasPrefix("secrets") { return true }
        if lower.hasSuffix(".pem") || lower.hasSuffix(".p12") || lower.hasSuffix(".key") || lower.hasSuffix(".keystore") || lower.hasSuffix(".mobileprovision") { return true }
        return false
    }

    static func scanFiles(root: URL) -> [ScannedFile] {
        let rootPath = root.path
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        var result = [ScannedFile]()
        while let fileURL = enumerator.nextObject() as? URL {
            let name = fileURL.lastPathComponent
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                if ignoredDirs.contains(name) || ignoredDirExtensions.contains(fileURL.pathExtension.lowercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }
            var rel = fileURL.path
            if rel.hasPrefix(rootPath + "/") { rel = String(rel.dropFirst(rootPath.count + 1)) }
            let ext = fileURL.pathExtension.lowercased()
            let base = fileURL.deletingPathExtension().lastPathComponent
            let lower = base.lowercased()
            let isTest = lower.hasSuffix("_test") || lower.hasSuffix(".test") || lower.hasSuffix(".spec")
                || lower.hasSuffix("tests") || lower.hasPrefix("test_") || rel.contains("/Tests/") || rel.hasPrefix("Tests/")
            result.append(ScannedFile(url: fileURL, path: rel, name: base, ext: ext,
                                      depth: rel.split(separator: "/").count - 1, isTest: isTest))
            if result.count >= maxFiles { break }
        }
        return result.sorted { $0.path < $1.path }
    }

    static func readText(_ url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.intValue <= maxFileBytes else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func nameVariants(candidates: [String]) -> [String] {
        var result = [String]()
        var seen = Set<String>()
        func add(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TermFormatter.normalized(t)
            guard t.count >= 3, !key.isEmpty, seen.insert(key).inserted else { return }
            result.append(t)
        }
        var primaryKeys = [String]()
        for (i, raw) in candidates.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = TermFormatter.normalized(trimmed)
            if i > 0, primaryKeys.contains(where: { key.hasPrefix($0) && key != $0 }) { continue }
            primaryKeys.append(key)
            add(TermFormatter.titleCased(TermFormatter.spoken(trimmed)))
            add(trimmed)
        }
        if let first = candidates.first {
            let words = TermFormatter.spoken(first).split(separator: " ")
            if words.count > 1, let w = words.first, w.count >= 5, !stopWords.contains(w.lowercased()) {
                add(TermFormatter.titleCased(String(w)))
            }
        }
        return Array(result.prefix(6))
    }

    static func readmeTitle(_ text: String) -> String? {
        guard let line = firstMatch(#"(?m)^#\s+(.+)$"#, in: text) else { return nil }
        let cleaned = String(line.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == " " || $0 == "-" || $0 == "_"
        }).trimmingCharacters(in: .whitespaces)
        let words = cleaned.split(separator: " ")
        return (1...4).contains(words.count) ? cleaned : nil
    }

    static func cleanReadme(_ text: String) -> String {
        var lines = [String]()
        var blank = 0
        var skippingFence = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if skippingFence { skippingFence = false; continue }
                if t.lowercased().hasPrefix("```mermaid") || t.lowercased().hasPrefix("```plantuml") { skippingFence = true; continue }
            }
            if skippingFence { continue }
            if t.hasPrefix("<") || t.hasPrefix("![") || t.hasPrefix("[![") { continue }
            if t.isEmpty { blank += 1; if blank > 1 { continue } } else { blank = 0 }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func readmeTerms(_ text: String) -> [String] {
        var out = [String]()
        let shape = try? NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z0-9 ._+\-]*$"#)
        let noiseWords: Set<String> = ["note", "warning", "tip", "important", "example", "caution", "todo", "settings"]

        func accept(_ s: String, titleCaseOnly: Bool) -> Bool {
            let t = s.trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            let words = t.split(separator: " ")
            guard t.count >= 4, t.count <= 32, words.count <= 4, let firstWord = words.first else { return false }
            if noiseWords.contains(firstWord.lowercased()) { return false }
            let range = NSRange(location: 0, length: (t as NSString).length)
            guard shape?.firstMatch(in: t, options: [], range: range) != nil else { return false }
            if titleCaseOnly && words.count > 1 {
                return words.allSatisfy { $0.first?.isUppercase == true || $0.first?.isNumber == true }
            }
            return true
        }

        let patterns: [(String, Bool)] = [(#"`([^`\n]{3,32})`"#, false), (#"\*\*([^*\n]{3,40}?)\*\*"#, true)]
        for (pattern, titleOnly) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = NSString(string: text)
            re.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m = m, m.numberOfRanges > 1 else { return }
                let s = ns.substring(with: m.range(at: 1))
                if accept(s, titleCaseOnly: titleOnly) { out.append(s.trimmingCharacters(in: CharacterSet(charactersIn: " :"))) }
            }
        }
        return unique(out)
    }

    static func structureMap(_ files: [ScannedFile]) -> String {
        var byDir = [String: [String]]()
        for f in files where !f.isTest {
            let fileName = f.url.lastPathComponent
            guard structureExts.contains(f.ext) || structureNames.contains(fileName) else { continue }
            let dir = (f.path as NSString).deletingLastPathComponent
            byDir[dir.isEmpty ? "." : dir, default: []].append(fileName)
        }
        var lines = [String]()
        for dir in byDir.keys.sorted().prefix(60) {
            let names = byDir[dir] ?? []
            let shown = names.prefix(8).joined(separator: ", ")
            lines.append("\(dir)/: \(shown)\(names.count > 8 ? " (+\(names.count - 8) more)" : "")")
        }
        return lines.joined(separator: "\n")
    }

    static func isUsefulTerm(_ t: String) -> Bool {
        guard t.count >= 4, t.count <= 40, let first = t.first, first.isLetter else { return false }
        if t.contains(".") || t.contains("/") { return false }
        return !stopWords.contains(t.lowercased())
    }

    static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased()).inserted }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = NSString(string: text)
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
