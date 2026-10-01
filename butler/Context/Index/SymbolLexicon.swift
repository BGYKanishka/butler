import Foundation

struct SymbolLexicon: Sendable {
    let symbolsByNorm: [String: [Int64]]
    let filesByNorm: [String: [String]] // path or ID
    let projectNames: Set<String>
    
    init(db: SQLiteDatabase, contextNames: [String]) async {
        var syms = [String: [Int64]]()
        var files = [String: [String]]()
        
        let symRows = (try? await db.query("SELECT id, name_norm FROM symbols WHERE length(name) >= 4", rowMapper: { try ($0.int(at: 0), $0.text(at: 1)) })) ?? []
        for (id, norm) in symRows {
            syms[norm, default: []].append(id)
        }
        
        let fileRows = (try? await db.query("SELECT rel_path FROM files", rowMapper: { try $0.text(at: 0) })) ?? []
        for path in fileRows {
            let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let norm = TermFormatter.normalized(base)
            if norm.count >= 3 {
                files[norm, default: []].append(path)
            }
        }
        
        self.symbolsByNorm = syms
        self.filesByNorm = files
        self.projectNames = Set(contextNames.map { TermFormatter.normalized($0) })
    }
}
