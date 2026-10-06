import Foundation
import os

private let logger = Logger(subsystem: "com.butler", category: "RAG")

actor HybridProjectRetriever: ProjectRetrievalService {
    private let db: SQLiteDatabase

    // MARK: - Lexicon cache
    // The lexicon is a full table-scan of symbols+files. It only changes after an index sync,
    // so cache it for 60 seconds to avoid rebuilding on every question (and every partial transcript).
    private var cachedLexicon: SymbolLexicon?
    private var lexiconBuiltAt: Date = .distantPast
    private let lexiconTTL: TimeInterval = 60

    init(db: SQLiteDatabase) {
        self.db = db
    }

    /// Call this after a sync() completes so the next query gets a fresh lexicon.
    func invalidateLexiconCache() {
        cachedLexicon = nil
        logger.debug("Lexicon cache invalidated")
    }

    // MARK: - Public entry point

    func context(for text: String, recentTurns: [ConversationTurn], isFinal: Bool, budgetTokens: Int) async -> String {
        let lexicon = await freshLexicon()
        let query = QueryRouter.route(text: text, recentTurns: recentTurns, lexicon: lexicon)

        guard query.shouldRetrieve else { return "" }

        let chunks = await retrieve(query: query, budgetTokens: budgetTokens, cheapOnly: !isFinal)
        let multiProject = lexicon.projectNames.count > 1
        return ContextAssembler.assemble(chunks, budgetTokens: budgetTokens, multiProject: multiProject)
    }

    // MARK: - Lexicon

    private func freshLexicon() async -> SymbolLexicon {
        let now = Date()
        if let cached = cachedLexicon, now.timeIntervalSince(lexiconBuiltAt) < lexiconTTL {
            return cached
        }
        let names = (try? await db.query("SELECT name FROM projects", rowMapper: { $0.text(at: 0) })) ?? []
        let lex = await SymbolLexicon(db: db, contextNames: names)
        cachedLexicon = lex
        lexiconBuiltAt = now
        logger.debug("Lexicon rebuilt: \(lex.symbolsByNorm.count) symbols, \(lex.filesByNorm.count) files")
        return lex
    }

    // MARK: - Retrieval

    private func retrieve(query: RoutedQuery, budgetTokens: Int, cheapOnly: Bool) async -> [ScoredChunk] {
        var candidates = [RetrievalSource: [(Int64, Double)]]()

        // 1. Symbol — exact + prefix matches
        var symbolScores = [(Int64, Double)]()
        if !query.symbolHits.isEmpty {
            for hit in query.symbolHits {
                let rows = (try? await db.query(
                    "SELECT c.id FROM chunks c JOIN symbols s ON c.symbol_id = s.id WHERE s.name_norm = ?",
                    binds: [.text(hit)], rowMapper: { $0.int(at: 0) })) ?? []
                for r in rows { symbolScores.append((r, 1.0)) }

                // Prefix search is more expensive; skip on partial/cheap queries.
                if !cheapOnly {
                    let prefixRows = (try? await db.query(
                        "SELECT c.id FROM chunks c JOIN symbols s ON c.symbol_id = s.id WHERE s.name_norm LIKE ? LIMIT 10",
                        binds: [.text(hit + "%")], rowMapper: { $0.int(at: 0) })) ?? []
                    for r in prefixRows { symbolScores.append((r, 0.5)) }
                }
            }
        }
        candidates[.symbol] = symbolScores

        // 2. Path
        var pathScores = [(Int64, Double)]()
        if !query.fileHits.isEmpty {
            for hit in query.fileHits {
                let rows = (try? await db.query(
                    "SELECT c.id FROM chunks c JOIN files f ON c.file_id = f.id WHERE f.rel_path LIKE ? LIMIT 10",
                    binds: [.text("%\(hit)%")], rowMapper: { $0.int(at: 0) })) ?? []
                for r in rows { pathScores.append((r, 1.0)) }
            }
        }
        candidates[.path] = pathScores

        // 3. Lexical (FTS5 / BM25)
        // Limit to 10 results on cheap/partial queries to reduce DB time.
        var lexicalScores = [(Int64, Double)]()
        let matchString = query.ftsTerms.map { "\"\($0)\"" }.joined(separator: " OR ")
        if !matchString.isEmpty {
            let limit = cheapOnly ? 10 : 20
            let sql = "SELECT rowid, bm25(chunks_fts, 8.0, 3.0, 4.0, 1.0) FROM chunks_fts WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts, 8.0, 3.0, 4.0, 1.0) LIMIT \(limit)"
            let rows = (try? await db.query(sql, binds: [.text(matchString)], rowMapper: { row -> (Int64, Double) in
                (row.int(at: 0), row.double(at: 1))
            })) ?? []
            // bm25() returns negative values in SQLite — negate so higher = better.
            for r in rows { lexicalScores.append((r.0, -r.1)) }
        }
        candidates[.lexical] = lexicalScores

        // Fusion — Reciprocal Rank Fusion (RRF, k=60)
        var chunkScores = [Int64: Double]()
        var chunkSources = [Int64: Set<RetrievalSource>]()
        let weights = weightsForIntent(query.intent)

        for (source, list) in candidates {
            let w = weights[source] ?? 0.0
            guard w > 0, !list.isEmpty else { continue }
            for (rank, item) in list.sorted(by: { $0.1 > $1.1 }).enumerated() {
                let cId = item.0
                chunkScores[cId, default: 0.0] += w / Double(60 + rank + 1)
                chunkSources[cId, default: Set()].insert(source)
            }
        }

        guard !chunkScores.isEmpty else { return [] }

        // MARK: Batch chunk fetch (fix: was N+1 individual queries)
        // Collect all candidate IDs and fetch them in one SQL call.
        let allIDs = Array(chunkScores.keys)
        let placeholders = allIDs.map { _ in "?" }.joined(separator: ", ")
        let batchSQL = """
            SELECT c.id, f.rel_path, s.name, s.qualified, s.kind,
                   c.start_line, c.end_line, c.content, c.content_hash, c.token_est,
                   p.name, p.root_path
            FROM chunks c
            JOIN files f ON c.file_id = f.id
            JOIN projects p ON f.project_id = p.id
            LEFT JOIN symbols s ON c.symbol_id = s.id
            WHERE c.id IN (\(placeholders))
            """
        let binds = allIDs.map { SQLValue.int($0) }
        var scoredChunks: [ScoredChunk] = (try? await db.query(batchSQL, binds: binds) { row -> ScoredChunk? in
            let cId = row.int(at: 0)
            guard let score = chunkScores[cId] else { return nil }
            let chunk = CodeChunk(
                id: cId,
                relPath: row.text(at: 1),
                symbolName: row.isNull(at: 2) ? nil : row.text(at: 2),
                qualifiedName: row.isNull(at: 3) ? nil : row.text(at: 3),
                kind: row.isNull(at: 4) ? "chunk" : row.text(at: 4),
                startLine: Int(row.int(at: 5)),
                endLine: Int(row.int(at: 6)),
                content: row.text(at: 7),
                contentHash: row.text(at: 8),
                tokenEstimate: Int(row.int(at: 9))
            )
            return ScoredChunk(chunk: chunk, score: score,
                               sources: chunkSources[cId] ?? [],
                               projectLabel: row.text(at: 10),
                               projectRoot: row.text(at: 11))
        })?.compactMap { $0 } ?? []

        scoredChunks.sort { $0.score > $1.score }

        // Post-processing: cap, per-file limit, overlap dedup
        var finalChunks = [ScoredChunk]()
        var fileCounts = [String: Int]()
        var selectedIDs = Set<Int64>()

        for var sc in scoredChunks {
            if finalChunks.count >= 8 { break }
            let isTest = sc.chunk.relPath.lowercased().contains("test")
            if isTest && !query.text.lowercased().contains("test") { sc.score *= 0.6 }

            let f = sc.chunk.relPath
            if fileCounts[f, default: 0] >= 2 { continue }

            let hasOverlap = finalChunks.contains { other in
                guard other.chunk.relPath == sc.chunk.relPath else { return false }
                let oStart = max(sc.chunk.startLine, other.chunk.startLine)
                let oEnd   = min(sc.chunk.endLine,   other.chunk.endLine)
                guard oStart <= oEnd else { return false }
                let myLen = sc.chunk.endLine - sc.chunk.startLine + 1
                return Double(oEnd - oStart + 1) / Double(max(1, myLen)) > 0.5
            }
            if hasOverlap { continue }

            finalChunks.append(sc)
            selectedIDs.insert(sc.chunk.id)
            fileCounts[f, default: 0] += 1
        }

        // 4. 1-hop graph expansion — skip entirely on cheap/partial queries.
        if !cheapOnly && !finalChunks.isEmpty {
            var graphIDs = [Int64]()
            for sc in finalChunks.prefix(3) {
                let refIDs = (try? await db.query(
                    "SELECT c.id FROM refs r JOIN chunks c ON r.target_symbol_id = c.symbol_id WHERE r.src_chunk_id = ? LIMIT 4",
                    binds: [.int(sc.chunk.id)], rowMapper: { $0.int(at: 0) })) ?? []
                // Skip IDs that were already scored or selected to avoid duplicates.
                for gcId in refIDs where chunkScores[gcId] == nil && !selectedIDs.contains(gcId) {
                    graphIDs.append(gcId)
                    selectedIDs.insert(gcId) // prevent the same graph chunk being added twice
                }
            }

            if !graphIDs.isEmpty {
                let gPlaceholders = graphIDs.map { _ in "?" }.joined(separator: ", ")
                let gSQL = """
                    SELECT c.id, f.rel_path, s.name, s.qualified, s.kind,
                           c.start_line, c.end_line, c.content, c.content_hash, c.token_est,
                           p.name, p.root_path
                    FROM chunks c
                    JOIN files f ON c.file_id = f.id
                    JOIN projects p ON f.project_id = p.id
                    LEFT JOIN symbols s ON c.symbol_id = s.id
                    WHERE c.id IN (\(gPlaceholders))
                    """
                let baseScore = (finalChunks.last?.score ?? 0.1) * 0.3
                let graphChunks: [ScoredChunk] = (try? await db.query(gSQL, binds: graphIDs.map { SQLValue.int($0) }) { row -> ScoredChunk? in
                    let gcId = row.int(at: 0)
                    let chunk = CodeChunk(
                        id: gcId, relPath: row.text(at: 1),
                        symbolName: row.isNull(at: 2) ? nil : row.text(at: 2),
                        qualifiedName: row.isNull(at: 3) ? nil : row.text(at: 3),
                        kind: row.isNull(at: 4) ? "chunk" : row.text(at: 4),
                        startLine: Int(row.int(at: 5)), endLine: Int(row.int(at: 6)),
                        content: row.text(at: 7), contentHash: row.text(at: 8),
                        tokenEstimate: Int(row.int(at: 9))
                    )
                    return ScoredChunk(chunk: chunk, score: baseScore,
                                       sources: [.graph],
                                       projectLabel: row.text(at: 10),
                                       projectRoot: row.text(at: 11))
                })?.compactMap { $0 } ?? []
                finalChunks.append(contentsOf: graphChunks)
            }
        }

        // 5. Freshness check — drop chunks whose file has been modified since indexing.
        var freshChunks = [ScoredChunk]()
        for sc in finalChunks {
            let fileURL = URL(fileURLWithPath: sc.projectRoot).appendingPathComponent(sc.chunk.relPath)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                  let size = attrs[.size] as? Int64,
                  let mdate = attrs[.modificationDate] as? Date else {
                continue // file missing on disk — stale
            }
            let mtime = mdate.timeIntervalSince1970
            let checkSql = "SELECT f.size, f.mtime FROM files f JOIN chunks c ON c.file_id = f.id WHERE c.id = ?"
            if let rows = try? await db.query(checkSql, binds: [.int(sc.chunk.id)], rowMapper: { ($0.int(at: 0), $0.double(at: 1)) }),
               let dbData = rows.first {
                if dbData.0 != size || dbData.1 != mtime { continue } // stale
            }
            freshChunks.append(sc)
        }

        // Weak signal guard: if nothing specific was matched (only FTS), require a minimum score.
        // Use a lower threshold when the query has a general cue (what/how/why) because those
        // conversational questions have no symbol hits by design but still deserve context.
        let hasGeneralCueWords = !query.symbolHits.isEmpty || !query.fileHits.isEmpty ||
            ["how", "what", "why", "which", "where", "explain", "tell", "describe"]
                .contains(where: { query.text.lowercased().contains($0) })
        let minScore = hasGeneralCueWords ? 0.6 / 61.0 : 1.2 / 61.0
        if query.symbolHits.isEmpty && query.fileHits.isEmpty,
           let best = freshChunks.first, best.score < minScore {
            return []
        }

        logger.debug("Retrieval: \(freshChunks.count) chunks (\(cheapOnly ? "cheap" : "full") mode, intent: \(String(describing: query.intent)))")
        return freshChunks
    }

    // MARK: - Intent weights
    // Note: .semantic source is reserved for future embedding-based retrieval and is not populated yet.
    private func weightsForIntent(_ intent: QueryIntent) -> [RetrievalSource: Double] {
        switch intent {
        case .symbolLookup:   return [.symbol: 3.0, .path: 1.0, .lexical: 1.5]
        case .fileLookup:     return [.symbol: 1.5, .path: 3.0, .lexical: 1.0]
        case .implementation: return [.symbol: 1.5, .path: 0.7, .lexical: 1.5]
        case .architecture:   return [.symbol: 1.0, .path: 0.5, .lexical: 1.0]
        case .general:        return [.symbol: 1.0, .path: 0.5, .lexical: 1.5]
        }
    }
}
