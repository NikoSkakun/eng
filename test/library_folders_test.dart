import 'package:eng/src/data/app_database.dart';
import 'package:eng/src/models/library_document.dart';
import 'package:eng/src/state/library_controller.dart';
import 'package:eng/src/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.inMemory();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        libraryDirectoryProvider.overrideWithValue('/tmp'),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    db.dispose();
  });

  LibraryController ctrl() =>
      container.read(libraryControllerProvider.notifier);
  LibraryState st() => container.read(libraryControllerProvider);

  // Insert a document row directly (no file copy) for test setup.
  LibraryDocument addDoc(String title, {int? folderId}) {
    final doc = container
        .read(libraryRepositoryProvider)
        .insert(
          LibraryDocument(
            id: 0,
            title: title,
            filePath: '/tmp/$title.pdf',
            addedAt: DateTime.now(),
            folderId: folderId,
            position: st().countIn(folderId),
          ),
        );
    // ignore: invalid_use_of_protected_member
    container.invalidate(libraryControllerProvider);
    return doc;
  }

  test('nested folders + itemsIn lists folders before documents', () async {
    final a = await ctrl().createFolder('A');
    final b = await ctrl().createFolder('B', parentId: a.id);
    addDoc('doc', folderId: a.id);

    expect(st().childFolders(null).map((f) => f.name), ['A']);
    final inA = st().itemsIn(a.id);
    expect(inA.length, 2);
    expect(inA.first.isFolder, isTrue); // folder before document
    expect(inA.first.folder!.id, b.id);
    expect(inA.last.isFolder, isFalse);
    expect(st().childFolders(a.id).single.id, b.id);
  });

  test('moveItemTo reorders items within a level', () async {
    final a = await ctrl().createFolder('A');
    final b = await ctrl().createFolder('B');
    expect(st().itemsIn(null).map((i) => i.folder!.name), ['A', 'B']);

    // Move B to the front.
    final bItem = st().itemsIn(null).firstWhere((i) => i.folder!.id == b.id);
    ctrl().moveItemTo(item: bItem, targetParentId: null, gapIndex: 0);
    expect(st().itemsIn(null).map((i) => i.folder!.name), ['B', 'A']);
    expect(a, isNotNull);
  });

  test('moveItemTo gap reordering lands items at the expected index', () async {
    await ctrl().createFolder('A');
    await ctrl().createFolder('B');
    await ctrl().createFolder('C');
    List<String> order() =>
        st().itemsIn(null).map((i) => i.folder!.name).toList();
    LibraryItem item(String name) =>
        st().itemsIn(null).firstWhere((i) => i.folder!.name == name);
    expect(order(), ['A', 'B', 'C']);

    // Move A (index 0) down past B, into the gap between B and C (gap 2).
    ctrl().moveItemTo(item: item('A'), targetParentId: null, gapIndex: 2);
    expect(order(), ['B', 'A', 'C']);

    // Move A to the end (gap 3).
    ctrl().moveItemTo(item: item('A'), targetParentId: null, gapIndex: 3);
    expect(order(), ['B', 'C', 'A']);

    // Move A back to the front (gap 0).
    ctrl().moveItemTo(item: item('A'), targetParentId: null, gapIndex: 0);
    expect(order(), ['A', 'B', 'C']);

    // Drop into the gap immediately after itself (gap 1) — a no-op.
    ctrl().moveItemTo(item: item('A'), targetParentId: null, gapIndex: 1);
    expect(order(), ['A', 'B', 'C']);

    // Move C (index 2) up into gap 1.
    ctrl().moveItemTo(item: item('C'), targetParentId: null, gapIndex: 1);
    expect(order(), ['A', 'C', 'B']);
  });

  test('moveItemTo moves a document into a folder (append)', () async {
    final a = await ctrl().createFolder('A');
    final doc = addDoc('paper');
    expect(st().documentsIn(null).map((d) => d.id), [doc.id]);

    ctrl().moveItemTo(item: LibraryItem.document(doc), targetParentId: a.id);
    expect(st().documentsIn(null), isEmpty);
    expect(st().documentsIn(a.id).single.id, doc.id);
  });

  test('moveItemTo nests a folder under another', () async {
    final a = await ctrl().createFolder('A');
    final b = await ctrl().createFolder('B');
    final ok = ctrl().moveItemTo(
      item: LibraryItem.folder(b),
      targetParentId: a.id,
    );
    expect(ok, isTrue);
    expect(st().childFolders(null).map((f) => f.id), [a.id]);
    expect(st().childFolders(a.id).single.id, b.id);
  });

  test(
    'moveItemTo refuses to nest a folder inside its own descendant',
    () async {
      final a = await ctrl().createFolder('A');
      final b = await ctrl().createFolder('B', parentId: a.id);
      // Try to move A under B (B is a child of A) — would create a cycle.
      final aItem = st().childFolders(null).map(LibraryItem.folder).single;
      final ok = ctrl().moveItemTo(item: aItem, targetParentId: b.id);
      expect(ok, isFalse);
      expect(st().folderById(a.id)!.parentId, isNull); // unchanged
      expect(st().folderById(b.id)!.parentId, a.id); // unchanged
    },
  );

  test('deleting a folder moves its children up to its parent', () async {
    final a = await ctrl().createFolder('A');
    final b = await ctrl().createFolder('B', parentId: a.id);
    final doc = addDoc('doc', folderId: a.id);

    ctrl().deleteFolder(st().folderById(a.id)!);
    expect(st().folderById(a.id), isNull);
    // B and doc moved up to A's parent (root).
    expect(st().folderById(b.id)!.parentId, isNull);
    expect(
      container.read(libraryRepositoryProvider).getById(doc.id)!.folderId,
      isNull,
    );
  });
}
