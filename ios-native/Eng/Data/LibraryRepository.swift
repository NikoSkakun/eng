import Foundation

/// Reads/writes `LibraryDocument` rows.
struct LibraryRepository {
    let db: Database

    private func map(_ r: Row) -> LibraryDocument {
        LibraryDocument(
            id: r.int64(0),
            title: r.string(1),
            fileName: r.string(2),
            originalPath: r.optString(3),
            pageCount: r.int(4),
            addedAt: r.date(5),
            lastOpenedAt: r.optDate(6),
            lastPage: r.int(7),
            viewMatrix: r.optString(8))
    }

    private static let columns = "id, title, file_name, original_path, page_count, added_at, last_opened_at, last_page, view_matrix"

    func fetchAll() throws -> [LibraryDocument] {
        try db.query("SELECT \(Self.columns) FROM documents ORDER BY " +
            "COALESCE(last_opened_at, added_at) DESC;", [], map)
    }

    @discardableResult
    func insert(_ d: LibraryDocument) throws -> Int64 {
        try db.run("""
            INSERT INTO documents(title, file_name, original_path, page_count, added_at, last_opened_at, last_page)
            VALUES(?,?,?,?,?,?,?);
            """, [d.title, d.fileName, d.originalPath, d.pageCount, d.addedAt, d.lastOpenedAt, d.lastPage])
    }

    func updateProgress(id: Int64, lastPage: Int, viewMatrix: String?) throws {
        try db.run("UPDATE documents SET last_page=?, last_opened_at=?, view_matrix=? WHERE id=?;",
                   [lastPage, Date(), viewMatrix, id])
    }

    func rename(id: Int64, title: String) throws {
        try db.run("UPDATE documents SET title=? WHERE id=?;", [title, id])
    }

    func delete(_ id: Int64) throws { try db.run("DELETE FROM documents WHERE id=?;", [id]) }
}
