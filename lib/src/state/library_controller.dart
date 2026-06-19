import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/library_document.dart';
import '../models/library_folder.dart';
import 'providers.dart';

/// A single library entry shown at some level: a folder or a document.
class LibraryItem {
  const LibraryItem.folder(LibraryFolder this.folder) : document = null;
  const LibraryItem.document(LibraryDocument this.document) : folder = null;

  final LibraryFolder? folder;
  final LibraryDocument? document;

  bool get isFolder => folder != null;
  int get id => folder?.id ?? document!.id;
  int get position => folder?.position ?? document!.position;

  /// Stable identity key (folder and document ids live in separate spaces).
  String get key => isFolder ? 'f$id' : 'd$id';
}

/// Immutable snapshot of the library: its folders and all documents.
class LibraryState {
  LibraryState({required this.folders, required this.documents})
    : _foldersById = {for (final f in folders) f.id: f};

  final List<LibraryFolder> folders;
  final List<LibraryDocument> documents;
  final Map<int, LibraryFolder> _foldersById;

  LibraryFolder? folderById(int id) => _foldersById[id];

  /// Folders directly inside [parentId] (root when null).
  List<LibraryFolder> childFolders(int? parentId) =>
      folders.where((f) => f.parentId == parentId).toList();

  /// Documents directly inside [folderId] (root when null).
  List<LibraryDocument> documentsIn(int? folderId) =>
      documents.where((d) => d.folderId == folderId).toList();

  /// Number of items (folders + documents) directly inside [parentId].
  int countIn(int? parentId) =>
      childFolders(parentId).length + documentsIn(parentId).length;

  /// The ordered items (folders + documents) directly inside [parentId].
  List<LibraryItem> itemsIn(int? parentId) {
    final items = <LibraryItem>[
      for (final f in childFolders(parentId)) LibraryItem.folder(f),
      for (final d in documentsIn(parentId)) LibraryItem.document(d),
    ];
    items.sort(_compare);
    return items;
  }

  static int _compare(LibraryItem a, LibraryItem b) {
    final byPos = a.position.compareTo(b.position);
    if (byPos != 0) return byPos;
    // Tiebreak before any manual ordering: folders first, then folders by name
    // and documents by most-recently-opened.
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    if (a.isFolder) {
      return a.folder!.name.toLowerCase().compareTo(
        b.folder!.name.toLowerCase(),
      );
    }
    final ad = a.document!.lastOpenedAt ?? a.document!.addedAt;
    final bd = b.document!.lastOpenedAt ?? b.document!.addedAt;
    return bd.compareTo(ad);
  }
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

  Future<LibraryFolder> createFolder(String name, {int? parentId}) async {
    final folder = ref
        .read(libraryRepositoryProvider)
        .insertFolder(
          LibraryFolder(
            id: 0,
            name: name.trim(),
            createdAt: DateTime.now(),
            parentId: parentId,
            position: state.countIn(parentId), // append at the end of the level
          ),
        );
    _reload();
    return folder;
  }

  void renameFolder(LibraryFolder folder, String name) {
    ref.read(libraryRepositoryProvider).renameFolder(folder.id, name.trim());
    _reload();
  }

  /// Delete a folder; its child folders and documents move up to the deleted
  /// folder's own parent (appended after the existing items there) so nothing
  /// is lost and ordering stays clean.
  void deleteFolder(LibraryFolder folder) {
    final repo = ref.read(libraryRepositoryProvider);
    final dest = folder.parentId;
    final existing = state
        .itemsIn(dest)
        .where((it) => !(it.isFolder && it.folder!.id == folder.id))
        .toList();
    final moved = state.itemsIn(folder.id);
    repo.deleteFolder(folder.id, newParentId: dest);
    final ordered = [...existing, ...moved];
    for (var i = 0; i < ordered.length; i++) {
      final it = ordered[i];
      if (it.isFolder) {
        repo.setFolderParent(it.folder!.id, dest, position: i);
      } else {
        repo.setDocumentFolder(it.document!.id, dest, position: i);
      }
    }
    _reload();
  }

  /// Move [item] so it becomes a child of [targetParentId] (root when null).
  ///
  /// With [gapIndex] the item is placed at that slot among the destination's
  /// items (used for drag-to-reorder / drop-between); without it the item is
  /// appended (used for drop-onto-folder). Returns false without changes if the
  /// move would nest a folder inside itself or one of its descendants.
  bool moveItemTo({
    required LibraryItem item,
    required int? targetParentId,
    int? gapIndex,
  }) {
    if (item.isFolder && _wouldCycle(item.folder!.id, targetParentId)) {
      return false;
    }
    final repo = ref.read(libraryRepositoryProvider);
    final siblings = state.itemsIn(targetParentId);
    final oldIndex = siblings.indexWhere((it) => it.key == item.key);
    final ordered = [...siblings]..removeWhere((it) => it.key == item.key);

    int insertAt;
    if (gapIndex == null) {
      insertAt = ordered.length; // append (drop onto a folder)
    } else {
      // gapIndex counts slots in the displayed list (which still includes the
      // moved item when reordering within the same level), so shift down by one
      // when moving an item further down its own level.
      insertAt = (oldIndex != -1 && gapIndex > oldIndex)
          ? gapIndex - 1
          : gapIndex;
      insertAt = insertAt.clamp(0, ordered.length);
    }
    ordered.insert(insertAt, item);

    for (var i = 0; i < ordered.length; i++) {
      final it = ordered[i];
      if (it.isFolder) {
        repo.setFolderParent(it.folder!.id, targetParentId, position: i);
      } else {
        repo.setDocumentFolder(it.document!.id, targetParentId, position: i);
      }
    }
    _reload();
    return true;
  }

  /// Move a document into [folderId] (root when null), appended at the end.
  void moveToFolder(LibraryDocument doc, int? folderId) {
    moveItemTo(item: LibraryItem.document(doc), targetParentId: folderId);
  }

  /// Whether [item] may be dropped into the folder [targetFolderId]: always for
  /// a document; for a folder, not into itself or one of its descendants.
  bool canMoveInto(LibraryItem item, int? targetFolderId) {
    if (!item.isFolder) return true;
    if (item.folder!.id == targetFolderId) return false;
    return !_wouldCycle(item.folder!.id, targetFolderId);
  }

  /// Whether re-parenting folder [folderId] under [targetParentId] would create
  /// a cycle (target is the folder itself or one of its descendants).
  bool _wouldCycle(int folderId, int? targetParentId) {
    if (targetParentId == null) return false;
    if (targetParentId == folderId) return true;
    final seen = <int>{};
    var current = state.folderById(targetParentId);
    while (current != null) {
      if (current.id == folderId) return true;
      if (!seen.add(current.id)) break; // guard against pre-existing cycles
      final parent = current.parentId;
      current = parent == null ? null : state.folderById(parent);
    }
    return false;
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
            position: state.countIn(folderId), // append at the end of the level
          ),
        );
    _reload();
    // Scan the new document for every existing term in the background, so their
    // cached usages include it without waiting until it's first opened.
    ref.read(usageIndexerProvider).indexNewDocument(saved.id);
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
