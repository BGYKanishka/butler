import Foundation

actor ProjectIndexCoordinator {
    private let db: SQLiteDatabase
    private var currentState: IndexState = .idle
    private let chunker = CodeChunker()
    
    init(dbPath: String) throws {
        self.db = try SQLiteDatabase(path: dbPath)
    }
    
    private func initSchema() async throws {
        for cmd in IndexSchema.sqlCommands {
            _ = try await db.exec(cmd)
        }
        // Check version
        let storedVersion = (try? await db.query("SELECT value FROM meta WHERE key = 'schema_version'", rowMapper: { $0.text(at: 0) }).first) ?? "0"
        if storedVersion != String(IndexSchema.version) {
            // In a real app, delete DB and recreate. For simplicity, just update here.
            _ = try await db.exec("INSERT OR REPLACE INTO meta(key, value) VALUES ('schema_version', ?)", binds: [.text(String(IndexSchema.version))])
        }
    }
    
    func sync(projects: [URL]) async {
        do { try await initSchema() } catch { print("Schema init failed: \(error)"); return }
        currentState = .indexing(done: 0, total: 0)
        
        for root in projects {
            guard !Task.isCancelled else { break }
            await syncSingleProject(root: root)
        }
        
        if !Task.isCancelled {
            let files = (try? await db.query("SELECT COUNT(*) FROM files", rowMapper: { $0.int(at: 0) }).first) ?? 0
            let chunks = (try? await db.query("SELECT COUNT(*) FROM chunks", rowMapper: { $0.int(at: 0) }).first) ?? 0
            currentState = .ready(files: Int(files), chunks: Int(chunks))
        }
    }
    
    private func syncSingleProject(root: URL) async {
        let canonicalPath = root.resolvingSymlinksInPath().path
        let projectID = String(FileFingerprint.sha256(of: canonicalPath).prefix(16))
        
        do {
            _ = try await db.exec("INSERT OR IGNORE INTO projects(id, root_path, name, indexed_at) VALUES (?, ?, ?, ?)",
                                  binds: [.text(projectID), .text(canonicalPath), .text(root.lastPathComponent), .double(Date().timeIntervalSince1970)])
            
            var changedChunks = [(id: Int64, content: String)]()
            
            var scanned = ProjectScanner.scanFiles(root: root)
            let allowedExts = ProjectScanner.sourceExts.union(["md", "yml", "yaml", "toml", "sh", "proto", "sql", "gradle"])
            scanned = scanned.filter { f in
                !ProjectScanner.isSecretLike(f.name) &&
                (allowedExts.contains(f.ext) || ProjectScanner.structureNames.contains(f.name))
            }
            if scanned.count > 5000 { scanned = Array(scanned.prefix(5000)) } // Cap at 5000
            
            // Load stored files
            let stored = try await db.query("SELECT id, rel_path, size, mtime, content_hash FROM files WHERE project_id = ?", binds: [.text(projectID)]) { row -> (Int64, String, Int64, Double, String) in
                return (row.int(at: 0), row.text(at: 1), row.int(at: 2), row.double(at: 3), row.text(at: 4))
            }
            var storedDict = [String: (id: Int64, size: Int64, mtime: Double, hash: String)]()
            for s in stored { storedDict[s.1] = (s.0, s.2, s.3, s.4) }
            
            var processed = 0
            let total = scanned.count
            
            for file in scanned {
                if Task.isCancelled { break }
                processed += 1
                if processed % 50 == 0 { currentState = .indexing(done: processed, total: total) }
                
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.url.path),
                      let size = attrs[.size] as? Int64,
                      let mdate = attrs[.modificationDate] as? Date else { continue }
                let mtime = mdate.timeIntervalSince1970
                
                if let s = storedDict[file.path], s.size == size, s.mtime == mtime {
                    storedDict.removeValue(forKey: file.path)
                    continue
                }
                
                guard let text = ProjectScanner.readText(file.url) else { continue }
                if text.count > 200_000 { continue }
                if text.components(separatedBy: .newlines).map({ $0.count }).reduce(0, +) / max(1, text.components(separatedBy: .newlines).count) > 300 { continue }
                
                let hash = FileFingerprint.sha256(of: text)
                if let s = storedDict[file.path], s.hash == hash {
                    _ = try await db.exec("UPDATE files SET mtime = ?, size = ? WHERE id = ?", binds: [.double(mtime), .int(size), .int(s.id)])
                    storedDict.removeValue(forKey: file.path)
                    continue
                }
                
                // Re-index
                try await db.transaction {
                    if let s = storedDict[file.path] {
                        _ = try await self.db.exec("DELETE FROM chunks_fts WHERE rowid IN (SELECT id FROM chunks WHERE file_id = ?)", binds: [.int(s.id)])
                        _ = try await self.db.exec("DELETE FROM files WHERE id = ?", binds: [.int(s.id)])
                    }
                    
                    _ = try await self.db.exec("INSERT INTO files(project_id, rel_path, language, size, mtime, content_hash, is_test) VALUES (?, ?, ?, ?, ?, ?, ?)",
                                          binds: [.text(projectID), .text(file.path), .text(file.ext), .int(size), .double(mtime), .text(hash), .int(file.isTest ? 1 : 0)])
                    let fileId = await self.db.lastInsertRowID
                    
                    let (symbols, chunks) = self.chunker.chunk(relPath: file.path, ext: file.ext, text: text)
                    var symIdMap = [String: Int64]()
                    
                    for sym in symbols {
                        let norm = TermFormatter.normalized(sym.name)
                        _ = try await self.db.exec("INSERT INTO symbols(project_id, file_id, name, name_norm, qualified, kind, parent, start_line, end_line) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                              binds: [.text(projectID), .int(fileId), .text(sym.name), .text(norm), .text(sym.qualified), .text(sym.kind), sym.parent != nil ? .text(sym.parent!) : .null, .int(Int64(sym.startLine)), .int(Int64(sym.endLine))])
                        symIdMap[sym.name] = await self.db.lastInsertRowID
                    }
                    
                    for (i, chunk) in chunks.enumerated() {
                        let sId = chunk.symbolName.flatMap { symIdMap[$0] }
                        _ = try await self.db.exec("INSERT INTO chunks(project_id, file_id, symbol_id, chunk_index, start_line, end_line, content, content_hash, token_est) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                              binds: [.text(projectID), .int(fileId), sId != nil ? .int(sId!) : .null, .int(Int64(i)), .int(Int64(chunk.startLine)), .int(Int64(chunk.endLine)), .text(chunk.content), .text(chunk.contentHash), .int(Int64(chunk.tokenEstimate))])
                        let chunkId = await self.db.lastInsertRowID
                        changedChunks.append((id: chunkId, content: chunk.content))
                        
                        let words = TermFormatter.spoken(chunk.qualifiedName ?? "").lowercased()
                        _ = try await self.db.exec("INSERT INTO chunks_fts(rowid, symbol, path, words, content) VALUES (?, ?, ?, ?, ?)",
                                              binds: [.int(chunkId), .text(chunk.qualifiedName ?? ""), .text(chunk.relPath), .text(words), .text(chunk.content)])
                    }
                }
                storedDict.removeValue(forKey: file.path)
            }
            
            // Delete missing files
            for s in storedDict.values {
                try await db.transaction {
                    _ = try await self.db.exec("DELETE FROM chunks_fts WHERE rowid IN (SELECT id FROM chunks WHERE file_id = ?)", binds: [.int(s.id)])
                    _ = try await self.db.exec("DELETE FROM files WHERE id = ?", binds: [.int(s.id)])
                }
            }
            
            if !changedChunks.isEmpty {
                await buildGraphRefs(projectID: projectID, newChunks: changedChunks)
            }
            
            _ = try await db.exec("UPDATE projects SET indexed_at = ? WHERE id = ?", binds: [.double(Date().timeIntervalSince1970), .text(projectID)])
            
        } catch {
            print("ProjectIndexCoordinator error: \(error)")
            currentState = .failed(error.localizedDescription)
        }
    }
    
    private func buildGraphRefs(projectID: String, newChunks: [(id: Int64, content: String)]) async {
        do {
            let uniqueSymbols = (try? await db.query(
                "SELECT name_norm, id FROM symbols WHERE project_id = ? GROUP BY name_norm HAVING COUNT(*) = 1",
                binds: [.text(projectID)]
            ) { row -> (String, Int64) in
                (row.text(at: 0), row.int(at: 1))
            }) ?? []
            
            var symbolMap = [String: Int64]()
            for s in uniqueSymbols { symbolMap[s.0] = s.1 }
            
            let stopList: Set<String> = ["main", "init", "self", "this", "super", "string", "int", "bool", "true", "false", "void", "print", "count", "data"]
            let regex = try NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]{3,}")
            
            try await db.transaction {
                for chunk in newChunks {
                    let range = NSRange(chunk.content.startIndex..<chunk.content.endIndex, in: chunk.content)
                    let matches = regex.matches(in: chunk.content, range: range)
                    
                    var refsFound = Set<Int64>()
                    for match in matches {
                        guard let rng = Range(match.range, in: chunk.content) else { continue }
                        let word = String(chunk.content[rng])
                        let norm = TermFormatter.normalized(word)
                        if stopList.contains(norm) { continue }
                        
                        if let symId = symbolMap[norm] {
                            refsFound.insert(symId)
                            if refsFound.count >= 12 { break }
                        }
                    }
                    
                    for symId in refsFound {
                        _ = try await db.exec("INSERT OR IGNORE INTO refs(src_chunk_id, target_symbol_id) VALUES (?, ?)", binds: [.int(chunk.id), .int(symId)])
                    }
                }
            }
        } catch {
            print("Failed to build graph refs: \(error)")
        }
    }
    
    func removeProject(root: URL) async {
        let canonicalPath = root.resolvingSymlinksInPath().path
        let projectID = String(FileFingerprint.sha256(of: canonicalPath).prefix(16))
        do {
            try await db.transaction {
                _ = try await self.db.exec("DELETE FROM chunks_fts WHERE rowid IN (SELECT id FROM chunks WHERE project_id = ?)", binds: [.text(projectID)])
                _ = try await self.db.exec("DELETE FROM projects WHERE id = ?", binds: [.text(projectID)])
            }
        } catch {
            print("Failed to remove project: \(error)")
        }
    }
    
    func state() -> IndexState {
        return currentState
    }
}
