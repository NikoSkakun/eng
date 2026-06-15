import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/library_document.dart';
import 'providers.dart';

final libraryControllerProvider =
    NotifierProvider<LibraryController, List<LibraryDocument>>(
      LibraryController.new,
    );

class LibraryController extends Notifier<List<LibraryDocument>> {
  @override
  List<LibraryDocument> build() => ref.read(libraryRepositoryProvider).getAll();

  void _reload() => state = ref.read(libraryRepositoryProvider).getAll();

  /// Copy the PDF at [sourcePath] into the managed library directory and record
  /// it. The library is self-contained, so the original may be moved/deleted
  /// afterwards.
  Future<LibraryDocument> importFromPath(
    String sourcePath, {
    String? title,
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

  void rename(LibraryDocument doc, String title) {
    final repo = ref.read(libraryRepositoryProvider);
    final current = repo.getById(doc.id) ?? doc;
    repo.update(current.copyWith(title: title));
    _reload();
  }
}
