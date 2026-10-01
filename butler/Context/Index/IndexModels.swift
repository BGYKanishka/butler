import Foundation

struct IndexedFile: Sendable { let id: Int64; let relPath: String; let language: String
                               let size: Int64; let mtime: Double; let contentHash: String; let isTest: Bool }
struct IndexedSymbol: Sendable { let id: Int64; let fileID: Int64; let name: String; let qualified: String
                                 let kind: String; let parent: String?; let startLine: Int; let endLine: Int }
struct ChunkedSymbol: Sendable { let name: String; let qualified: String; let kind: String; let parent: String?
                                 let startLine: Int; let endLine: Int }
struct CodeChunk: Sendable { var id: Int64 = 0; let relPath: String; let symbolName: String?
                             let qualifiedName: String?; let kind: String; let startLine: Int; let endLine: Int
                             let content: String; let contentHash: String; let tokenEstimate: Int }

enum QueryIntent: Sendable {
    case symbolLookup
    case fileLookup
    case architecture
    case implementation
    case general
}

struct RoutedQuery: Sendable {
    let intent: QueryIntent
    let shouldRetrieve: Bool
    let symbolHits: [String]
    let fileHits: [String]
    let ftsTerms: [String]
    let text: String
}
enum RetrievalSource: String, Sendable { case symbol, path, lexical, semantic, graph }
struct ScoredChunk: Sendable { let chunk: CodeChunk; var score: Double; var sources: Set<RetrievalSource>; let projectLabel: String }
enum IndexState: Sendable, Equatable { case idle, indexing(done: Int, total: Int), ready(files: Int, chunks: Int), failed(String) }
