import 'package:sqlite3/sqlite3.dart';

import '../models/library_document.dart';
import 'app_database.dart';

/// Persistence for the document library.
class LibraryRepository {
  LibraryRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  List<LibraryDocument> getAll() {
    final rows = _db.select(
      'SELECT * FROM documents ORDER BY COALESCE(last_opened_at, added_at) DESC;',
    );
    return rows.map(_fromRow).toList();
  }

  LibraryDocument? getById(int id) {
    final rows = _db.select('SELECT * FROM documents WHERE id = ? LIMIT 1;', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  LibraryDocument insert(LibraryDocument doc) {
    _db.execute(
      '''
      INSERT INTO documents(title, file_path, original_path, page_count, added_at, last_opened_at, last_page)
      VALUES(?,?,?,?,?,?,?);
      ''',
      [
        doc.title,
        doc.filePath,
        doc.originalPath,
        doc.pageCount,
        doc.addedAt.millisecondsSinceEpoch,
        doc.lastOpenedAt?.millisecondsSinceEpoch,
        doc.lastPage,
      ],
    );
    return doc.copyWith(id: _db.lastInsertRowId);
  }

  void update(LibraryDocument doc) {
    _db.execute(
      '''
      UPDATE documents SET
        title = ?, file_path = ?, original_path = ?, page_count = ?,
        last_opened_at = ?, last_page = ?
      WHERE id = ?;
      ''',
      [
        doc.title,
        doc.filePath,
        doc.originalPath,
        doc.pageCount,
        doc.lastOpenedAt?.millisecondsSinceEpoch,
        doc.lastPage,
        doc.id,
      ],
    );
  }

  void delete(int id) {
    _db.execute('DELETE FROM documents WHERE id = ?;', [id]);
  }

  LibraryDocument _fromRow(Row row) {
    final lastOpened = row['last_opened_at'] as int?;
    return LibraryDocument(
      id: row['id'] as int,
      title: row['title'] as String,
      filePath: row['file_path'] as String,
      originalPath: row['original_path'] as String?,
      pageCount: row['page_count'] as int,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
      lastOpenedAt: lastOpened == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastOpened),
      lastPage: row['last_page'] as int,
    );
  }
}
