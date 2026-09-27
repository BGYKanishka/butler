import Foundation

struct ProjectContextData: Equatable {
    let vocabulary: [String]
    let summary: String
}

protocol ProjectAnalyzerService: Sendable {
    func analyzeProject(at url: URL) async throws -> ProjectContextData
}

actor ProjectAnalyzer: ProjectAnalyzerService {
    func analyzeProject(at url: URL) async throws -> ProjectContextData {
        var vocabulary = Set<String>()
        var techStack = Set<String>()
        
        let fileManager = FileManager.default
        let ignoredDirs = Set(["node_modules", "Pods", "build", ".build", ".git", "vendor", "dist", "target"])
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return ProjectContextData(vocabulary: [], summary: "")
        }
        
        var fileCount = 0
        var readmeContent = ""
        var configContent = ""
        var sourceCodeContent = ""
        var maxSourceChars = 60000 // Roughly 15k-20k tokens
        
        for case let fileURL as URL in enumerator {
            // Check if we need to skip ignored directories
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            
            let filename = fileURL.lastPathComponent
            
            if isDirectory && ignoredDirs.contains(filename) {
                enumerator.skipDescendants()
                continue
            }
            
            if !isDirectory {
                let ext = fileURL.pathExtension.lowercased()
                
                // Read README for project context
                if filename.lowercased().hasPrefix("readme") && readmeContent.isEmpty {
                    if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                        readmeContent = String(text.prefix(2000)) 
                    }
                }
                
                // Read Config files for project context
                if (filename == "package.json" || filename == "project.yml" || filename == "Cargo.toml") && configContent.isEmpty {
                    if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                        configContent = String(text.prefix(1500)) 
                    }
                }
                
                let isSourceFile = ["swift", "js", "ts", "tsx", "jsx", "py", "go", "java", "kt", "rs", "cpp", "h", "c", "mm", "m"].contains(ext)
                
                if isSourceFile && sourceCodeContent.count < maxSourceChars {
                    if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                        sourceCodeContent += "\n--- \(filename) ---\n"
                        sourceCodeContent += String(text.prefix(4000)) // Max 4000 chars per file to get diverse files
                    }
                }
                
                // Extract tech stack and vocabulary
                if ext == "swift" {
                    techStack.insert("Swift")
                    vocabulary.insert(fileURL.deletingPathExtension().lastPathComponent)
                } else if ext == "js" || ext == "ts" || ext == "tsx" || ext == "jsx" {
                    techStack.insert(ext.contains("ts") ? "TypeScript" : "JavaScript")
                    if ext.contains("x") { techStack.insert("React") }
                    vocabulary.insert(fileURL.deletingPathExtension().lastPathComponent)
                } else if ext == "py" {
                    techStack.insert("Python")
                } else if ext == "go" {
                    techStack.insert("Go")
                } else if ext == "java" || ext == "kt" {
                    techStack.insert(ext == "kt" ? "Kotlin" : "Java")
                    techStack.insert("Spring") // Heuristic
                } else if filename == "package.json" {
                    techStack.insert("Node.js")
                } else if filename == "Podfile" {
                    techStack.insert("CocoaPods")
                } else if filename == "Cargo.toml" {
                    techStack.insert("Rust")
                } else if filename == "docker-compose.yml" || filename == "Dockerfile" {
                    techStack.insert("Docker")
                }
                
                fileCount += 1
                if fileCount > 3000 {
                    break // Prevent hanging on massive repos
                }
            }
        }
        
        let projectName = url.lastPathComponent
        let stackString = techStack.isEmpty ? "unknown technologies" : techStack.joined(separator: ", ")
        var summary = "The user is actively working in a codebase/project named '\(projectName)' which relies on the following technologies: \(stackString)."
        
        if !readmeContent.isEmpty {
            summary += "\n\nPROJECT README EXCERPT:\n\(readmeContent)"
        }
        if !configContent.isEmpty {
            summary += "\n\nPROJECT CONFIG EXCERPT:\n\(configContent)"
        }
        if !sourceCodeContent.isEmpty {
            summary += "\n\nSOURCE CODE EXCERPTS:\n\(sourceCodeContent)"
        }
        
        // Filter out short or unhelpful vocabulary words
        let filteredVocab = vocabulary.filter { $0.count > 3 }
        
        return ProjectContextData(vocabulary: Array(filteredVocab), summary: summary)
    }
}
