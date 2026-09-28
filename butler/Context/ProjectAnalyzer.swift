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
        let ignoredDirs = Set(["node_modules", "Pods", "build", ".build", ".git", "vendor", "dist", "target", "out", "bin"])
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return ProjectContextData(vocabulary: [], summary: "")
        }
        
        var filePaths = [String]()
        var readmeContent = ""
        var configContent = ""
        var sourceCodeContent = ""
        let maxSourceChars = 60000 
        var fileCount = 0
        
        var importantFiles = [(String, String)]() // (filename, content)
        var generalFiles = [(String, String)]()
        
        while let fileURL = enumerator.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let filename = fileURL.lastPathComponent
            
            if isDirectory && ignoredDirs.contains(filename) {
                enumerator.skipDescendants()
                continue
            }
            
            if !isDirectory {
                let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                filePaths.append(relativePath)
                
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
                
                if isSourceFile {
                    if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                        // Prioritize main, index, app, core files
                        let isImportant = filename.lowercased().contains("main") || filename.lowercased().contains("index") || filename.lowercased().contains("app") || filename.lowercased().contains("core")
                        
                        if isImportant {
                            importantFiles.append((relativePath, String(text.prefix(4000))))
                        } else {
                            // Random sample of other files
                            if generalFiles.count < 20 {
                                generalFiles.append((relativePath, String(text.prefix(2000))))
                            }
                        }
                    }
                }
                
                // Extract tech stack and vocabulary
                if ext == "swift" {
                    techStack.insert("Swift")
                    vocabulary.insert(fileURL.deletingPathExtension().lastPathComponent)
                } else if ["mm", "m", "cpp", "c", "h"].contains(ext) {
                    techStack.insert("C/C++/Obj-C")
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
                    break 
                }
            }
        }
        
        for (path, content) in importantFiles {
            if sourceCodeContent.count < maxSourceChars {
                sourceCodeContent += "\n--- \(path) ---\n\(content)"
            }
        }
        for (path, content) in generalFiles {
            if sourceCodeContent.count < maxSourceChars {
                sourceCodeContent += "\n--- \(path) ---\n\(content)"
            }
        }
        
        let projectName = url.lastPathComponent
        let stackString = techStack.isEmpty ? "unknown technologies" : techStack.joined(separator: ", ")
        var summary = "The candidate's project is named '\(projectName)' and relies on: \(stackString)."
        
        let treeSummary = filePaths.prefix(150).joined(separator: "\n")
        summary += "\n\nPROJECT STRUCTURE (Top files):\n\(treeSummary)"
        
        if !readmeContent.isEmpty {
            summary += "\n\nPROJECT README EXCERPT:\n\(readmeContent)"
        }
        if !configContent.isEmpty {
            summary += "\n\nPROJECT CONFIG EXCERPT:\n\(configContent)"
        }
        if !sourceCodeContent.isEmpty {
            summary += "\n\nSOURCE CODE EXCERPTS:\n\(sourceCodeContent)"
        }
        
        let filteredVocab = vocabulary.filter { $0.count > 3 }
        
        summary += "\n\nPROJECT VOCABULARY (Use this to correct phonetic transcription errors):\n\(filteredVocab.prefix(150).joined(separator: ", "))"
        
        return ProjectContextData(vocabulary: Array(filteredVocab), summary: summary)
    }
}
