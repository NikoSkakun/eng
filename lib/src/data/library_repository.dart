import 'package:sqlite3/sqlite3.dart';

import '../models/library_document.dart';
import '../models/library_folder.dart';
import 'app_database.dart';

/// Persistence for the document library.
class LibraryRepository {
  LibraryRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  // --- Folders ---

  List<LibraryFolder> getAllFolders() {
    final rows = _db.select(
      'SELECT * FROM folders ORDER BY name COLLATE NOCASE;',
    );
    return rows.map(_folderFromRow).toList();
  }

  LibraryFolder insertFolder(LibraryFolder folder) {
    _db.execute('INSERT INTO folders(name, created_at) VALUES(?,?);', [
      folder.name,
      folder.createdAt.millisecondsSinceEpoch,
    ]);
    return folder.copyWith(id: _db.lastInsertRowId);
  }

  void renameFolder(int id, String name) {
    _db.execute('UPDATE folders SET name = ? WHERE id = ?;', [name, id]);
  }

  /// Delete a folder; its documents are kept and moved back to the root.
  void deleteFolder(int id) {
    _db.execute('UPDATE documents SET folder_id = NULL WHERE folder_id = ?;', [
      id,
    ]);
    _db.execute('DELETE FROM folders WHERE id = ?;', [id]);
  }

  /// Move a document into [folderId] (or to the root when null).
  void setDocumentFolder(int docId, int? folderId) {
    _db.execute('UPDATE documents SET folder_id = ? WHERE id = ?;', [
      folderId,
      docId,
    ]);
  }

  LibraryFolder _folderFromRow(Row row) => LibraryFolder(
    id: row['id'] as int,
    name: row['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
  );

  // --- Documents ---

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
      INSERT INTO documents(title, file_path, original_path, page_count, added_at, last_opened_at, last_page, view_matrix, folder_id)
      VALUES(?,?,?,?,?,?,?,?,?);
      ''',
      [
        doc.title,
        doc.filePath,
        doc.originalPath,
        doc.pageCount,
        doc.addedAt.millisecondsSinceEpoch,
        doc.lastOpenedAt?.millisecondsSinceEpoch,
        doc.lastPage,
        doc.viewMatrix,
        doc.folderId,
      ],
    );
    return doc.copyWith(id: _db.lastInsertRowId);
  }

  void update(LibraryDocument doc) {
    _db.execute(
      '''
      UPDATE documents SET
        title = ?, file_path = ?, original_path = ?, page_count = ?,
        last_opened_at = ?, last_page = ?, view_matrix = ?, folder_id = ?
      WHERE id = ?;
      ''',
      [
        doc.title,
        doc.filePath,
        doc.originalPath,
        doc.pageCount,
        doc.lastOpenedAt?.millisecondsSinceEpoch,
        doc.lastPage,
        doc.viewMatrix,
        doc.folderId,
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
      viewMatrix: row['view_matrix'] as String?,
      folderId: row['folder_id'] as int?,
    );
  }
}
