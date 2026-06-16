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
    final rows = _db.select('SELECT * FROM folders;');
    return rows.map(_folderFromRow).toList();
  }

  LibraryFolder insertFolder(LibraryFolder folder) {
    _db.execute(
      'INSERT INTO folders(name, created_at, parent_id, position) '
      'VALUES(?,?,?,?);',
      [
        folder.name,
        folder.createdAt.millisecondsSinceEpoch,
        folder.parentId,
        folder.position,
      ],
    );
    return folder.copyWith(id: _db.lastInsertRowId);
  }

  void renameFolder(int id, String name) {
    _db.execute('UPDATE folders SET name = ? WHERE id = ?;', [name, id]);
  }

  /// Delete a folder, moving its child folders and documents up to
  /// [newParentId] (the deleted folder's own parent) so nothing is lost.
  void deleteFolder(int id, {int? newParentId}) {
    _db.execute('UPDATE folders SET parent_id = ? WHERE parent_id = ?;', [
      newParentId,
      id,
    ]);
    _db.execute('UPDATE documents SET folder_id = ? WHERE folder_id = ?;', [
      newParentId,
      id,
    ]);
    _db.execute('DELETE FROM folders WHERE id = ?;', [id]);
  }

  /// Move a document into [folderId] (or to the root when null), optionally
  /// setting its [position].
  void setDocumentFolder(int docId, int? folderId, {int? position}) {
    if (position == null) {
      _db.execute('UPDATE documents SET folder_id = ? WHERE id = ?;', [
        folderId,
        docId,
      ]);
    } else {
      _db.execute(
        'UPDATE documents SET folder_id = ?, position = ? WHERE id = ?;',
        [folderId, position, docId],
      );
    }
  }

  /// Move a folder under [parentId] (or to the root when null), optionally
  /// setting its [position].
  void setFolderParent(int folderId, int? parentId, {int? position}) {
    if (position == null) {
      _db.execute('UPDATE folders SET parent_id = ? WHERE id = ?;', [
        parentId,
        folderId,
      ]);
    } else {
      _db.execute(
        'UPDATE folders SET parent_id = ?, position = ? WHERE id = ?;',
        [parentId, position, folderId],
      );
    }
  }

  void setFolderPosition(int folderId, int position) {
    _db.execute('UPDATE folders SET position = ? WHERE id = ?;', [
      position,
      folderId,
    ]);
  }

  void setDocumentPosition(int docId, int position) {
    _db.execute('UPDATE documents SET position = ? WHERE id = ?;', [
      position,
      docId,
    ]);
  }

  LibraryFolder _folderFromRow(Row row) => LibraryFolder(
    id: row['id'] as int,
    name: row['name'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    parentId: row['parent_id'] as int?,
    position: (row['position'] as int?) ?? 0,
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
      INSERT INTO documents(title, file_path, original_path, page_count, added_at, last_opened_at, last_page, view_matrix, folder_id, position)
      VALUES(?,?,?,?,?,?,?,?,?,?);
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
        doc.position,
      ],
    );
    return doc.copyWith(id: _db.lastInsertRowId);
  }

  void update(LibraryDocument doc) {
    _db.execute(
      '''
      UPDATE documents SET
        title = ?, file_path = ?, original_path = ?, page_count = ?,
        last_opened_at = ?, last_page = ?, view_matrix = ?, folder_id = ?,
        position = ?
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
        doc.position,
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
      position: (row['position'] as int?) ?? 0,
    );
  }
}
