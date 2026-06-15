import 'package:sqlite3/sqlite3.dart';

import '../models/dictionary_entry.dart';
import 'app_database.dart';

/// Persistence for [DictionaryEntry] rows.
class DictionaryRepository {
  DictionaryRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  /// All entries, newest first.
  List<DictionaryEntry> getAll() {
    final rows = _db.select(
      'SELECT * FROM dictionary ORDER BY updated_at DESC;',
    );
    return rows.map(_fromRow).toList();
  }

  DictionaryEntry? getById(int id) {
    final rows = _db.select('SELECT * FROM dictionary WHERE id = ? LIMIT 1;', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Find an entry by its normalized term, optionally restricted to a document
  /// scope. Used to avoid creating duplicates.
  DictionaryEntry? findByNormalized(
    String normalizedTerm, {
    int? scopeDocumentId,
  }) {
    final ResultSet rows;
    if (scopeDocumentId == null) {
      rows = _db.select(
        'SELECT * FROM dictionary WHERE normalized_term = ? AND scope_document_id IS NULL LIMIT 1;',
        [normalizedTerm],
      );
    } else {
      rows = _db.select(
        'SELECT * FROM dictionary WHERE normalized_term = ? AND scope_document_id = ? LIMIT 1;',
        [normalizedTerm, scopeDocumentId],
      );
    }
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Insert [entry] and return it with its assigned id.
  DictionaryEntry insert(DictionaryEntry entry) {
    _db.execute(
      '''
      INSERT INTO dictionary(
        term, normalized_term, source_lang, target_lang, translation, definition,
        notes, highlight_enabled, color_value, scope_document_id, created_at, updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?);
      ''',
      [
        entry.term,
        entry.normalizedTerm,
        entry.sourceLang,
        entry.targetLang,
        entry.translation,
        entry.definition,
        entry.notes,
        entry.highlightEnabled ? 1 : 0,
        entry.colorValue,
        entry.scopeDocumentId,
        entry.createdAt.millisecondsSinceEpoch,
        entry.updatedAt.millisecondsSinceEpoch,
      ],
    );
    return entry.copyWith(id: _db.lastInsertRowId);
  }

  void update(DictionaryEntry entry) {
    _db.execute(
      '''
      UPDATE dictionary SET
        term = ?, normalized_term = ?, source_lang = ?, target_lang = ?,
        translation = ?, definition = ?, notes = ?, highlight_enabled = ?,
        color_value = ?, scope_document_id = ?, updated_at = ?
      WHERE id = ?;
      ''',
      [
        entry.term,
        entry.normalizedTerm,
        entry.sourceLang,
        entry.targetLang,
        entry.translation,
        entry.definition,
        entry.notes,
        entry.highlightEnabled ? 1 : 0,
        entry.colorValue,
        entry.scopeDocumentId,
        entry.updatedAt.millisecondsSinceEpoch,
        entry.id,
      ],
    );
  }

  void delete(int id) {
    _db.execute('DELETE FROM dictionary WHERE id = ?;', [id]);
  }

  DictionaryEntry _fromRow(Row row) {
    return DictionaryEntry(
      id: row['id'] as int,
      term: row['term'] as String,
      sourceLang: row['source_lang'] as String,
      targetLang: row['target_lang'] as String,
      translation: row['translation'] as String?,
      definition: row['definition'] as String?,
      notes: row['notes'] as String?,
      highlightEnabled: (row['highlight_enabled'] as int) != 0,
      colorValue: row['color_value'] as int?,
      scopeDocumentId: row['scope_document_id'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
