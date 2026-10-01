import Foundation
import SQLite3

enum SQLValue: Sendable {
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

struct SQLRow {
    let stmt: OpaquePointer
    
    func int(at index: Int32) -> Int64 { sqlite3_column_int64(stmt, index) }
    func double(at index: Int32) -> Double { sqlite3_column_double(stmt, index) }
    func text(at index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }
    func blob(at index: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(stmt, index) else { return Data() }
        let length = sqlite3_column_bytes(stmt, index)
        return Data(bytes: bytes, count: Int(length))
    }
    func isNull(at index: Int32) -> Bool { sqlite3_column_type(stmt, index) == SQLITE_NULL }
}

enum SQLiteError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case executionFailed(String)
}

actor SQLiteDatabase {
    private var db: OpaquePointer?
    
    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            db = nil
            throw SQLiteError.openFailed(msg)
        }
        
        let pragmaSQL = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        PRAGMA foreign_keys=ON;
        PRAGMA temp_store=MEMORY;
        """
        if sqlite3_exec(db, pragmaSQL, nil, nil, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            print("Warning: failed to set pragmas: \(msg)")
        }
    }
    
    deinit {
        if let db = db { sqlite3_close(db) }
    }
    
    @discardableResult
    func exec(_ sql: String, binds: [SQLValue] = []) throws -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        try bind(values: binds, to: stmt!)
        
        var changes = 0
        var stepResult = sqlite3_step(stmt)
        while stepResult == SQLITE_ROW {
            stepResult = sqlite3_step(stmt)
        }
        
        if stepResult != SQLITE_DONE {
            throw SQLiteError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        
        changes = Int(sqlite3_changes(db))
        return changes
    }
    
    func query<T>(_ sql: String, binds: [SQLValue] = [], rowMapper: (SQLRow) throws -> T) throws -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        
        try bind(values: binds, to: stmt!)
        
        var results = [T]()
        let row = SQLRow(stmt: stmt!)
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(try rowMapper(row))
        }
        return results
    }
    
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    private func bind(values: [SQLValue], to stmt: OpaquePointer) throws {
        for (i, val) in values.enumerated() {
            let idx = Int32(i + 1)
            let result: Int32
            switch val {
            case .int(let v): result = sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): result = sqlite3_bind_double(stmt, idx, v)
            case .text(let v):
                result = sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                result = v.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, idx, ptr.baseAddress, Int32(v.count), SQLITE_TRANSIENT)
                }
            case .null: result = sqlite3_bind_null(stmt, idx)
            }
            if result != SQLITE_OK {
                throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    
    func transaction<T>(_ block: () async throws -> T) async throws -> T {
        try exec("BEGIN TRANSACTION;")
        do {
            let result = try await block()
            try exec("COMMIT;")
            return result
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }
    
    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(db)
    }
}
