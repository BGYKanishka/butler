import Foundation

actor HybridProjectRetriever: ProjectRetrievalService {
    private let db: SQLiteDatabase
    
    init(db: SQLiteDatabase) {
        self.db = db
    }
    
    func context(for text: String, recentTurns: [ConversationTurn], isFinal: Bool, budgetTokens: Int) async -> String {
        let names = (try? await db.query("SELECT name FROM projects", rowMapper: { $0.text(at: 0) })) ?? []
        let lexicon = await SymbolLexicon(db: db, contextNames: names)
        let query = QueryRouter.route(text: text, recentTurns: recentTurns, lexicon: lexicon)
        
        guard query.shouldRetrieve else { return "" }
        
        let chunks = await retrieve(query: query, budgetTokens: budgetTokens, cheapOnly: !isFinal)
        return ContextAssembler.assemble(chunks, budgetTokens: budgetTokens, multiProject: names.count > 1)
    }
    
    private func retrieve(query: RoutedQuery, budgetTokens: Int, cheapOnly: Bool) async -> [ScoredChunk] {
        var candidates = [RetrievalSource: [(Int64, Double)]]()
        
        // 1. Symbol
        var symbolScores = [(Int64, Double)]()
        if !query.symbolHits.isEmpty {
            for hit in query.symbolHits {
                let rows = (try? await db.query("SELECT c.id FROM chunks c JOIN symbols s ON c.symbol_id = s.id WHERE s.name_norm = ?", binds: [.text(hit)], rowMapper: { $0.int(at: 0) })) ?? []
                for r in rows { symbolScores.append((r, 1.0)) }
                
                let prefixRows = (try? await db.query("SELECT c.id FROM chunks c JOIN symbols s ON c.symbol_id = s.id WHERE s.name_norm LIKE ? LIMIT 10", binds: [.text(hit + "%")], rowMapper: { $0.int(at: 0) })) ?? []
                for r in prefixRows { symbolScores.append((r, 0.5)) }
            }
        }
        candidates[.symbol] = symbolScores
        
        // 2. Path
        var pathScores = [(Int64, Double)]()
        if !query.fileHits.isEmpty {
            for hit in query.fileHits {
                let rows = (try? await db.query("SELECT c.id FROM chunks c JOIN files f ON c.file_id = f.id WHERE f.rel_path LIKE ? LIMIT 10", binds: [.text("%\(hit)%")], rowMapper: { $0.int(at: 0) })) ?? []
                for r in rows { pathScores.append((r, 1.0)) }
            }
        }
        candidates[.path] = pathScores
        
        // 3. Lexical (FTS5)
        var lexicalScores = [(Int64, Double)]()
        let matchString = query.ftsTerms.map { "\"\($0)\"" }.joined(separator: " OR ")
        if !matchString.isEmpty {
            let sql = "SELECT rowid, bm25(chunks_fts, 8.0, 3.0, 4.0, 1.0) FROM chunks_fts WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts, 8.0, 3.0, 4.0, 1.0) LIMIT 20"
            let rows = (try? await db.query(sql, binds: [.text(matchString)], rowMapper: { row -> (Int64, Double) in
                return (row.int(at: 0), row.double(at: 1))
            })) ?? []
            for r in rows { lexicalScores.append((r.0, -r.1)) } // bm25 returns negative score usually or we negate it depending on SQLite
        }
        candidates[.lexical] = lexicalScores
        
        // Fusion (RRF)
        var chunkScores = [Int64: Double]()
        var chunkSources = [Int64: Set<RetrievalSource>]()
        
        let weights = weightsForIntent(query.intent)
        
        for (source, list) in candidates {
            let w = weights[source] ?? 0.0
            guard w > 0, !list.isEmpty else { continue }
            
            // sort list by score descending
            let sorted = list.sorted { $0.1 > $1.1 }
            for (rank, item) in sorted.enumerated() {
                let cId = item.0
                let rrf = w / Double(60 + rank + 1)
                chunkScores[cId, default: 0.0] += rrf
                chunkSources[cId, default: Set()].insert(source)
            }
        }
        
        // Fetch chunks
        var scoredChunks = [ScoredChunk]()
        for (cId, score) in chunkScores {
            let sql = "SELECT f.rel_path, s.name, s.qualified, s.kind, c.start_line, c.end_line, c.content, c.content_hash, c.token_est, p.name, p.root_path FROM chunks c JOIN files f ON c.file_id = f.id JOIN projects p ON f.project_id = p.id LEFT JOIN symbols s ON c.symbol_id = s.id WHERE c.id = ?"
            if let rows = try? await db.query(sql, binds: [.int(cId)], rowMapper: { row -> ScoredChunk? in
                let chunk = CodeChunk(id: cId, relPath: row.text(at: 0), symbolName: row.isNull(at: 1) ? nil : row.text(at: 1), qualifiedName: row.isNull(at: 2) ? nil : row.text(at: 2), kind: row.isNull(at: 3) ? "chunk" : row.text(at: 3), startLine: Int(row.int(at: 4)), endLine: Int(row.int(at: 5)), content: row.text(at: 6), contentHash: row.text(at: 7), tokenEstimate: Int(row.int(at: 8)))
                let pName = row.text(at: 9)
                let pRoot = row.text(at: 10)
                return ScoredChunk(chunk: chunk, score: score, sources: chunkSources[cId] ?? [], projectLabel: pName, projectRoot: pRoot)
            }) {
                if let c = rows.first.flatMap({ $0 }) { scoredChunks.append(c) }
            }
        }
        
        scoredChunks.sort { $0.score > $1.score }
        
        // Post-processing
        var finalChunks = [ScoredChunk]()
        var fileCounts = [String: Int]()
        
        for var sc in scoredChunks {
            if finalChunks.count >= 8 { break }
            let isTest = sc.chunk.relPath.lowercased().contains("test")
            if isTest && !query.text.lowercased().contains("test") { sc.score *= 0.6 }
            
            let f = sc.chunk.relPath
            let count = fileCounts[f, default: 0]
            if count >= 2 { continue }
            
            // Check overlap
            let overlap = finalChunks.contains { other in
                guard other.chunk.relPath == sc.chunk.relPath else { return false }
                let overlapStart = max(sc.chunk.startLine, other.chunk.startLine)
                let overlapEnd = min(sc.chunk.endLine, other.chunk.endLine)
                if overlapStart > overlapEnd { return false }
                let len = overlapEnd - overlapStart + 1
                let myLen = sc.chunk.endLine - sc.chunk.startLine + 1
                return Double(len) / Double(max(1, myLen)) > 0.5
            }
            if overlap { continue }
            
            finalChunks.append(sc)
            fileCounts[f, default: 0] += 1
        }
        
        // 4. 1-hop graph expansion
        var graphChunks = [ScoredChunk]()
        for sc in finalChunks.prefix(3) {
            let sql = "SELECT c.id FROM refs r JOIN chunks c ON r.target_symbol_id = c.symbol_id WHERE r.src_chunk_id = ? LIMIT 4"
            if let rows = try? await db.query(sql, binds: [.int(sc.chunk.id)], rowMapper: { $0.int(at: 0) }) {
                for gcId in rows {
                    if chunkScores[gcId] != nil { continue }
                    chunkScores[gcId] = sc.score * 0.3
                    
                    let cSql = "SELECT f.rel_path, s.name, s.qualified, s.kind, c.start_line, c.end_line, c.content, c.content_hash, c.token_est, p.name, p.root_path FROM chunks c JOIN files f ON c.file_id = f.id JOIN projects p ON f.project_id = p.id LEFT JOIN symbols s ON c.symbol_id = s.id WHERE c.id = ?"
                    if let cRows = try? await db.query(cSql, binds: [.int(gcId)], rowMapper: { row -> ScoredChunk? in
                        let chunk = CodeChunk(id: gcId, relPath: row.text(at: 0), symbolName: row.isNull(at: 1) ? nil : row.text(at: 1), qualifiedName: row.isNull(at: 2) ? nil : row.text(at: 2), kind: row.isNull(at: 3) ? "chunk" : row.text(at: 3), startLine: Int(row.int(at: 4)), endLine: Int(row.int(at: 5)), content: row.text(at: 6), contentHash: row.text(at: 7), tokenEstimate: Int(row.int(at: 8)))
                        return ScoredChunk(chunk: chunk, score: sc.score * 0.3, sources: [.graph], projectLabel: row.text(at: 9), projectRoot: row.text(at: 10))
                    }) {
                        if let cg = cRows.first.flatMap({ $0 }) { graphChunks.append(cg) }
                    }
                }
            }
        }
        finalChunks.append(contentsOf: graphChunks)
        
        // 5. Freshness check
        var freshChunks = [ScoredChunk]()
        for sc in finalChunks {
            let fileURL = URL(fileURLWithPath: sc.projectRoot).appendingPathComponent(sc.chunk.relPath)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64,
               let mdate = attrs[.modificationDate] as? Date {
                let mtime = mdate.timeIntervalSince1970
                
                let checkSql = "SELECT size, mtime FROM files f JOIN chunks c ON c.file_id = f.id WHERE c.id = ?"
                if let rows = try? await db.query(checkSql, binds: [.int(sc.chunk.id)], rowMapper: { ($0.int(at: 0), $0.double(at: 1)) }), let dbData = rows.first {
                    if dbData.0 != size || dbData.1 != mtime {
                        continue // stale
                    }
                }
            } else {
                continue // missing
            }
            freshChunks.append(sc)
        }
        
        let minScore = 1.2 / 61.0
        if query.symbolHits.isEmpty && query.fileHits.isEmpty {
            if let best = freshChunks.first, best.score < minScore { return [] }
        }
        
        return freshChunks
    }
    
    private func weightsForIntent(_ intent: QueryIntent) -> [RetrievalSource: Double] {
        switch intent {
        case .symbolLookup: return [.symbol: 3.0, .path: 1.0, .lexical: 1.5, .semantic: 0.7]
        case .fileLookup: return [.symbol: 1.5, .path: 3.0, .lexical: 1.0, .semantic: 0.7]
        case .implementation: return [.symbol: 1.5, .path: 0.7, .lexical: 1.5, .semantic: 1.5]
        case .architecture: return [.symbol: 1.0, .path: 0.5, .lexical: 1.0, .semantic: 2.0]
        case .general: return [.symbol: 1.0, .path: 0.5, .lexical: 1.5, .semantic: 1.5]
        }
    }
}
