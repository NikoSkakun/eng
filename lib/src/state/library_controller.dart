import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/library_document.dart';
import '../models/library_folder.dart';
import 'providers.dart';

/// Immutable snapshot of the library: its folders and all documents.
class LibraryState {
  const LibraryState({required this.folders, required this.documents});

  final List<LibraryFolder> folders;
  final List<LibraryDocument> documents;

  /// Documents not filed under any folder (shown at the library root).
  List<LibraryDocument> get rootDocuments =>
      documents.where((d) => d.folderId == null).toList();

  /// Documents filed under [folderId].
  List<LibraryDocument> documentsIn(int folderId) =>
      documents.where((d) => d.folderId == folderId).toList();

  int countIn(int folderId) =>
      documents.where((d) => d.folderId == folderId).length;
}

final libraryControllerProvider =
    NotifierProvider<LibraryController, LibraryState>(LibraryController.new);

class LibraryController extends Notifier<LibraryState> {
  @override
  LibraryState build() => _read();

  LibraryState _read() {
    final repo = ref.read(libraryRepositoryProvider);
    return LibraryState(
      folders: repo.getAllFolders(),
      documents: repo.getAll(),
    );
  }

  void _reload() => state = _read();

  // --- Folders ---

  Future<LibraryFolder> createFolder(String name) async {
    final folder = ref
        .read(libraryRepositoryProvider)
        .insertFolder(
          LibraryFolder(id: 0, name: name.trim(), createdAt: DateTime.now()),
        );
    _reload();
    return folder;
  }

  void renameFolder(LibraryFolder folder, String name) {
    ref.read(libraryRepositoryProvider).renameFolder(folder.id, name.trim());
    _reload();
  }

  /// Delete a folder; its documents are moved back to the library root.
  void deleteFolder(LibraryFolder folder) {
    ref.read(libraryRepositoryProvider).deleteFolder(folder.id);
    _reload();
  }

  /// Move [doc] into [folderId] (or to the root when null).
  void moveToFolder(LibraryDocument doc, int? folderId) {
    ref.read(libraryRepositoryProvider).setDocumentFolder(doc.id, folderId);
    _reload();
  }

  /// Copy the PDF at [sourcePath] into the managed library directory and record
  /// it. The library is self-contained, so the original may be moved/deleted
  /// afterwards. Pass [folderId] to file the import into a folder.
  Future<LibraryDocument> importFromPath(
    String sourcePath, {
    String? title,
    int? folderId,
  }) async {
    final dir = ref.read(libraryDirectoryProvider);
    final baseName = p.basename(sourcePath);
    var dest = p.join(dir, baseName);
    var i = 1;
    while (File(dest).existsSync()) {
      final name =
          '${p.basenameWithoutExtension(baseName)} ($i)${p.extension(baseName)}';
      dest = p.join(dir, name);
      i++;
    }
    await File(sourcePath).copy(dest);

    final saved = ref
        .read(libraryRepositoryProvider)
        .insert(
          LibraryDocument(
            id: 0,
            title: title ?? p.basenameWithoutExtension(baseName),
            filePath: dest,
            originalPath: sourcePath,
            addedAt: DateTime.now(),
            folderId: folderId,
          ),
        );
    _reload();
    return saved;
  }

  Future<void> remove(LibraryDocument doc, {bool deleteFile = true}) async {
    ref.read(libraryRepositoryProvider).delete(doc.id);
    if (deleteFile) {
      final f = File(doc.filePath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {
          // Best-effort; the DB record is already gone.
        }
      }
    }
    _reload();
  }

  /// Update last-opened time and reading position.
  ///
  /// Each mutator re-reads the current row first so a full-row UPDATE built from
  /// a stale [doc] (e.g. one captured before the page count was known) does not
  /// clobber columns it didn't mean to change.
  void recordOpened(LibraryDocument doc, {int? page}) {
    final repo = ref.read(libraryRepositoryProvider);
    final current = repo.getById(doc.id) ?? doc;
    repo.update(
      current.copyWith(
        lastOpenedAt: DateTime.now(),
        lastPage: page ?? current.lastPage,
      ),
    );
    _reload();
  }

  void updatePageCount(LibraryDocument doc, int count) {
    if (count <= 0) return;
    final repo = ref.read(libraryRepositoryProvider);
    final current = repo.getById(doc.id) ?? doc;
    if (current.pageCount == count) return;
    repo.update(current.copyWith(pageCount: count));
    _reload();
  }

  /// Persist the exact reading view (page + serialized pdfrx matrix) so it can
  /// be restored when the document is reopened.
  void saveView(int docId, {required int page, required String viewMatrix}) {
    final repo = ref.read(libraryRepositoryProvider);
    final current = repo.getById(docId);
    if (current == null) return;
    if (current.lastPage == page && current.viewMatrix == viewMatrix) return;
    repo.update(current.copyWith(lastPage: page, viewMatrix: viewMatrix));
    _reload();
  }

  void rename(LibraryDocument doc, String title) {
    final repo = ref.read(libraryRepositoryProvider);
    final current = repo.getById(doc.id) ?? doc;
    repo.update(current.copyWith(title: title));
    _reload();
  }
}
