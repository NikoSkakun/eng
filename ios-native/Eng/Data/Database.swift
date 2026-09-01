import Foundation
import SQLite3

/// The SQLite destructor telling the library to copy bound bytes immediately.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// One row of a query result — thin accessors over a live statement.
struct Row {
    fileprivate let stmt: OpaquePointer?
    func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
    func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    func bool(_ i: Int32) -> Bool { sqlite3_column_int64(stmt, i) != 0 }
    func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    func string(_ i: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, i) else { return "" }
        return String(cString: c)
    }
    func optString(_ i: Int32) -> String? { isNull(i) ? nil : string(i) }
    func optInt64(_ i: Int32) -> Int64? { isNull(i) ? nil : int64(i) }
    func optInt(_ i: Int32) -> Int? { isNull(i) ? nil : int(i) }
    /// Epoch-millis integer column -> Date.
    func date(_ i: Int32) -> Date { Date(timeIntervalSince1970: double(i) / 1000.0) }
    func optDate(_ i: Int32) -> Date? { isNull(i) ? nil : date(i) }
}

/// Owns the SQLite connection and schema lifecycle. Uses `SQLite3` directly (no
/// ORM/codegen), matching the original app's design.
final class Database {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "eng.db")

    static let schemaVersion: Int32 = 2

    init(url: URL) throws {
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            throw dbError("open")
        }
        try exec("PRAGMA foreign_keys = ON;")
        try exec("PRAGMA journal_mode = WAL;")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    private func dbError(_ what: String) -> NSError {
        let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        return NSError(domain: "eng.db", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(what): \(msg)"])
    }

    /// Run one or more DDL/utility statements.
    func exec(_ sql: String) throws {
        try queue.sync {
            if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw dbError("exec") }
        }
    }

    /// Run a parametrized statement; returns the last inserted row id.
    @discardableResult
    func run(_ sql: String, _ params: [Any?] = []) throws -> Int64 {
        try queue.sync {
            let stmt = try prepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) != SQLITE_DONE { throw dbError("run") }
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// Run a query, mapping each row with `map`.
    func query<T>(_ sql: String, _ params: [Any?] = [], _ map: (Row) -> T) throws -> [T] {
        try queue.sync {
            let stmt = try prepare(sql, params)
            defer { sqlite3_finalize(stmt) }
            var out: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(map(Row(stmt: stmt))) }
            return out
        }
    }

    private func prepare(_ sql: String, _ params: [Any?]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK { throw dbError("prepare") }
        var idx: Int32 = 1
        for p in params {
            switch p {
            case nil, is NSNull:
                sqlite3_bind_null(stmt, idx)
            case let v as Bool:
                sqlite3_bind_int64(stmt, idx, v ? 1 : 0)
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, idx, v)
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            case let v as Date:
                sqlite3_bind_int64(stmt, idx, Int64(v.timeIntervalSince1970 * 1000))
            case let v as String:
                sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, SQLITE_TRANSIENT)
            default:
                sqlite3_bind_text(stmt, idx, ("\(p!)" as NSString).utf8String, -1, SQLITE_TRANSIENT)
            }
            idx += 1
        }
        return stmt
    }

    private func migrate() throws {
        var version = try query("PRAGMA user_version;") { $0.int(0) }.first ?? 0
        if version >= Int(Self.schemaVersion) { return }
        if version == 0 {
            // Fresh install: full latest schema (every later column included here).
            try exec("""
                CREATE TABLE documents(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  title TEXT NOT NULL,
                  file_name TEXT NOT NULL,
                  original_path TEXT,
                  page_count INTEGER NOT NULL DEFAULT 0,
                  added_at INTEGER NOT NULL,
                  last_opened_at INTEGER,
                  last_page INTEGER NOT NULL DEFAULT 1,
                  view_matrix TEXT
                );
                CREATE TABLE dictionary(
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  term TEXT NOT NULL,
                  normalized_term TEXT NOT NULL,
                  source_lang TEXT NOT NULL,
                  target_lang TEXT NOT NULL,
                  translation TEXT,
                  alt_translations TEXT,
                  definition TEXT,
                  notes TEXT,
                  highlight_enabled INTEGER NOT NULL DEFAULT 1,
                  color_value INTEGER,
                  match_partial INTEGER NOT NULL DEFAULT 0,
                  source_word TEXT,
                  scope_document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
                  created_at INTEGER NOT NULL,
                  updated_at INTEGER NOT NULL
                );
                CREATE INDEX idx_dictionary_normalized ON dictionary(normalized_term);
                CREATE INDEX idx_dictionary_scope ON dictionary(scope_document_id);
                CREATE TABLE cache(
                  cache_key TEXT PRIMARY KEY,
                  value TEXT NOT NULL,
                  created_at INTEGER NOT NULL
                );
            """)
            version = Int(Self.schemaVersion)
        }
        if version == 1 {
            // v1 -> v2: exact per-document saved view (position + zoom).
            try exec("ALTER TABLE documents ADD COLUMN view_matrix TEXT;")
            version = 2
        }
        try exec("PRAGMA user_version = \(Self.schemaVersion);")
    }
}
