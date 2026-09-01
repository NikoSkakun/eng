import Foundation

/// Reads/writes `DictionaryEntry` rows.
struct DictionaryRepository {
    let db: Database

    private static let columns = """
        id, term, normalized_term, source_lang, target_lang, translation, \
        alt_translations, definition, notes, highlight_enabled, color_value, \
        match_partial, source_word, scope_document_id, created_at, updated_at
        """

    private func map(_ r: Row) -> DictionaryEntry {
        DictionaryEntry(
            id: r.int64(0),
            term: r.string(1),
            sourceLang: r.string(3),
            targetLang: r.string(4),
            translation: r.optString(5),
            alternativeTranslations: Self.decodeAlts(r.optString(6)),
            definition: r.optString(7),
            notes: r.optString(8),
            highlightEnabled: r.bool(9),
            colorValue: r.optInt(10),
            matchPartial: r.bool(11),
            sourceWord: r.optString(12),
            scopeDocumentId: r.optInt64(13),
            createdAt: r.date(14),
            updatedAt: r.date(15))
    }

    func fetchAll() throws -> [DictionaryEntry] {
        try db.query("SELECT \(Self.columns) FROM dictionary ORDER BY term COLLATE NOCASE;", [], map)
    }

    /// Find a global (or same-document-scoped) entry with the same normalized key.
    func findByNormalized(_ key: String, scopeDocumentId: Int64?) throws -> DictionaryEntry? {
        let sql = "SELECT \(Self.columns) FROM dictionary WHERE normalized_term = ? " +
            "AND (scope_document_id IS NULL OR scope_document_id = ?) ORDER BY scope_document_id IS NULL LIMIT 1;"
        return try db.query(sql, [key, scopeDocumentId as Any?], map).first
    }

    @discardableResult
    func insert(_ e: DictionaryEntry) throws -> Int64 {
        try db.run("""
            INSERT INTO dictionary(term, normalized_term, source_lang, target_lang, translation,
              alt_translations, definition, notes, highlight_enabled, color_value, match_partial,
              source_word, scope_document_id, created_at, updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """, [e.term, e.normalizedTerm, e.sourceLang, e.targetLang, e.translation,
                  Self.encodeAlts(e.alternativeTranslations), e.definition, e.notes,
                  e.highlightEnabled, e.colorValue, e.matchPartial, e.sourceWord,
                  e.scopeDocumentId, e.createdAt, e.updatedAt])
    }

    func update(_ e: DictionaryEntry) throws {
        try db.run("""
            UPDATE dictionary SET term=?, normalized_term=?, source_lang=?, target_lang=?,
              translation=?, alt_translations=?, definition=?, notes=?, highlight_enabled=?,
              color_value=?, match_partial=?, source_word=?, scope_document_id=?, updated_at=?
            WHERE id=?;
            """, [e.term, e.normalizedTerm, e.sourceLang, e.targetLang, e.translation,
                  Self.encodeAlts(e.alternativeTranslations), e.definition, e.notes,
                  e.highlightEnabled, e.colorValue, e.matchPartial, e.sourceWord,
                  e.scopeDocumentId, Date(), e.id])
    }

    func delete(_ id: Int64) throws { try db.run("DELETE FROM dictionary WHERE id=?;", [id]) }

    // alt_translations is stored as a JSON array of strings (null = none).
    private static func encodeAlts(_ alts: [String]) -> String? {
        if alts.isEmpty { return nil }
        return String(data: (try? JSONSerialization.data(withJSONObject: alts)) ?? Data(), encoding: .utf8)
    }
    private static func decodeAlts(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return arr
    }
}
