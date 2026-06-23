import 'dart:io';

import 'package:eng/src/data/app_database.dart';
import 'package:eng/src/data/dictionary_repository.dart';
import 'package:eng/src/data/library_repository.dart';
import 'package:eng/src/data/usage_repository.dart';
import 'package:eng/src/models/dictionary_entry.dart';
import 'package:eng/src/models/library_document.dart';
import 'package:eng/src/models/usage.dart';
import 'package:eng/src/services/contexts/usage_indexer.dart';
import 'package:eng/src/services/contexts/word_contexts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<void> _until(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late AppDatabase db;
  late DictionaryRepository dict;
  late LibraryRepository lib;
  late UsageRepository usages;
  late Directory tmp;

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);

  setUp(() async {
    db = AppDatabase.inMemory();
    dict = DictionaryRepository(db);
    lib = LibraryRepository(db);
    usages = UsageRepository(db);
    tmp = await Directory.systemTemp.createTemp('eng_usage_test');
  });
  tearDown(() async {
    db.dispose();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  DictionaryEntry addEntry(String term) => dict.insert(
    DictionaryEntry(
      id: 0,
      term: term,
      sourceLang: 'en',
      targetLang: 'uk',
      createdAt: epoch,
      updatedAt: epoch,
    ),
  );

  LibraryDocument addDocRow(String path) => lib.insert(
    LibraryDocument(id: 0, title: 'Doc', filePath: path, addedAt: epoch),
  );

  Future<LibraryDocument> addTxt(String name, String body) async {
    final f = File(p.join(tmp.path, name));
    await f.writeAsString(body);
    return lib.insert(
      LibraryDocument(
        id: 0,
        title: p.basenameWithoutExtension(name),
        filePath: f.path,
        addedAt: epoch,
      ),
    );
  }

  Usage u(
    int entryId,
    int docId, {
    int? page,
    int? block,
    String snip = 'x',
    List<({int start, int end})> hl = const [(start: 0, end: 1)],
  }) => Usage(
    id: 0,
    entryId: entryId,
    documentId: docId,
    page: page,
    blockIndex: block,
    snippet: snip,
    highlights: hl,
  );

  group('UsageRepository', () {
    test(
      'putPair round-trips snippet/highlights/pointer and marks indexed',
      () {
        final e = addEntry('cat');
        final d = addDocRow('/a.txt');
        expect(usages.isIndexed(e.id, d.id), isFalse);

        usages.putPair(e.id, d.id, [
          u(e.id, d.id, page: 5, snip: 'a cat sat', hl: [(start: 2, end: 5)]),
          u(e.id, d.id, block: 3, snip: 'cat again', hl: [(start: 0, end: 3)]),
        ]);

        expect(usages.isIndexed(e.id, d.id), isTrue);
        expect(usages.indexedDocsForEntry(e.id), {d.id});
        final got = usages.forEntry(e.id);
        expect(got.length, 2);
        expect(got[0].page, 5);
        expect(got[0].snippet, 'a cat sat');
        expect(got[0].highlights, [(start: 2, end: 5)]);
        expect(got[1].blockIndex, 3);
      },
    );

    test('putPair replaces the prior result for the same pair', () {
      final e = addEntry('cat');
      final d = addDocRow('/a.txt');
      usages.putPair(e.id, d.id, [u(e.id, d.id, page: 1)]);
      usages.putPair(e.id, d.id, [
        u(e.id, d.id, page: 2),
        u(e.id, d.id, page: 3),
      ]);
      expect(usages.forEntry(e.id).length, 2);
    });

    test('clearEntry forgets usages and indexed marks', () {
      final e = addEntry('cat');
      final d = addDocRow('/a.txt');
      usages.putPair(e.id, d.id, [u(e.id, d.id)]);
      usages.clearEntry(e.id);
      expect(usages.forEntry(e.id), isEmpty);
      expect(usages.isIndexed(e.id, d.id), isFalse);
    });

    test('deleting the entry or the document cascades its usages away', () {
      final e = addEntry('cat');
      final d = addDocRow('/a.txt');
      usages.putPair(e.id, d.id, [u(e.id, d.id)]);
      dict.delete(e.id);
      expect(usages.forEntry(e.id), isEmpty);
      expect(usages.isIndexed(e.id, d.id), isFalse);

      final e2 = addEntry('dog');
      usages.putPair(e2.id, d.id, [u(e2.id, d.id)]);
      lib.delete(d.id);
      expect(usages.forEntry(e2.id), isEmpty);
    });
  });

  group('UsageIndexer', () {
    test(
      'reindexEntry scans the library and persists occurrence pointers',
      () async {
        final e = addEntry('cat');
        final d = await addTxt('a.txt', 'The cat sat.\n\nNo match here.');
        UsageIndexer(usages, dict, lib, WordContextsService()).reindexEntry(e);

        await _until(() => usages.isIndexed(e.id, d.id));
        final got = usages.forEntry(e.id);
        expect(got.length, 1);
        expect(got.single.documentId, d.id);
        expect(got.single.blockIndex, 0); // first paragraph
        expect(got.single.snippet, 'The cat sat.');
      },
    );

    test('ensureEntryIndexed picks up a newly added document', () async {
      final e = addEntry('cat');
      final d1 = await addTxt('a.txt', 'cat one');
      final indexer = UsageIndexer(usages, dict, lib, WordContextsService());
      indexer.reindexEntry(e);
      await _until(() => usages.indexedDocsForEntry(e.id).contains(d1.id));

      final d2 = await addTxt('b.txt', 'cat two');
      indexer.ensureEntryIndexed(e);
      await _until(() => usages.indexedDocsForEntry(e.id).contains(d2.id));

      expect(usages.forEntry(e.id).length, 2);
    });
  });
}
