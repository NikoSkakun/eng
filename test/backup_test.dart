import 'dart:io';

import 'package:eng/src/data/app_database.dart';
import 'package:eng/src/data/dictionary_repository.dart';
import 'package:eng/src/data/library_repository.dart';
import 'package:eng/src/models/dictionary_entry.dart';
import 'package:eng/src/models/library_document.dart';
import 'package:eng/src/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('eng_backup_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'export then import round-trips library + dictionary, remapping scope',
    () async {
      final srcDb = AppDatabase.inMemory();
      final srcLibDir = Directory(p.join(tmp.path, 'src'))..createSync();
      final srcLib = LibraryRepository(srcDb);
      final srcDict = DictionaryRepository(srcDb);

      final pdf = File(p.join(srcLibDir.path, 'doc.pdf'))
        ..writeAsBytesSync(List<int>.generate(2048, (i) => i % 256));
      final now = DateTime.now();
      final doc = srcLib.insert(
        LibraryDocument(
          id: 0,
          title: 'Doc',
          filePath: pdf.path,
          pageCount: 7,
          lastPage: 3,
          addedAt: now,
        ),
      );
      srcDict.insert(
        DictionaryEntry(
          id: 0,
          term: 'global term',
          sourceLang: 'en',
          targetLang: 'uk',
          translation: 'g',
          createdAt: now,
          updatedAt: now,
        ),
      );
      srcDict.insert(
        DictionaryEntry(
          id: 0,
          term: 'scoped term',
          sourceLang: 'en',
          targetLang: 'uk',
          translation: 's',
          scopeDocumentId: doc.id,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final zip = p.join(tmp.path, 'backup.zip');
      final exp = await BackupService(
        srcDict,
        srcLib,
        srcLibDir.path,
      ).exportTo(zip, includeLibrary: true, includeDictionary: true);
      expect(exp.documents, 1);
      expect(exp.entries, 2);
      expect(File(zip).existsSync(), isTrue);

      // Fresh destination, pre-seeded with a placeholder doc so the imported
      // document gets a *different* id — proving scope remapping really happens.
      final dstDb = AppDatabase.inMemory();
      final dstLibDir = Directory(p.join(tmp.path, 'dst'))..createSync();
      final dstLib = LibraryRepository(dstDb);
      final dstDict = DictionaryRepository(dstDb);
      final placeholder = dstLib.insert(
        LibraryDocument(
          id: 0,
          title: 'placeholder',
          filePath: '/nope.pdf',
          addedAt: now,
        ),
      );

      final svc = BackupService(dstDict, dstLib, dstLibDir.path);
      final info = await svc.inspect(zip);
      expect(info.documentCount, 1);
      expect(info.dictionaryCount, 2);

      final imp = await svc.importFrom(
        zip,
        includeLibrary: true,
        includeDictionary: true,
      );
      expect(imp.documents, 1);
      expect(imp.entries, 2);
      expect(imp.skipped, 0);

      final imported = dstLib.getAll().firstWhere((d) => d.title == 'Doc');
      expect(imported.id, isNot(placeholder.id));
      expect(imported.pageCount, 7);
      expect(imported.lastPage, 3);
      expect(File(imported.filePath).existsSync(), isTrue);
      expect(p.isWithin(dstLibDir.path, imported.filePath), isTrue);
      expect(File(imported.filePath).readAsBytesSync().length, 2048);

      final scoped = dstDict.getAll().firstWhere(
        (e) => e.term == 'scoped term',
      );
      expect(scoped.scopeDocumentId, imported.id); // remapped to the new id
      final global = dstDict.getAll().firstWhere(
        (e) => e.term == 'global term',
      );
      expect(global.scopeDocumentId, isNull);

      srcDb.dispose();
      dstDb.dispose();
    },
  );

  test('re-importing the same dictionary skips duplicates', () async {
    final db = AppDatabase.inMemory();
    final libDir = Directory(p.join(tmp.path, 'l'))..createSync();
    final lib = LibraryRepository(db);
    final dict = DictionaryRepository(db);
    final now = DateTime.now();
    for (final t in ['alpha', 'beta', 'gamma']) {
      dict.insert(
        DictionaryEntry(
          id: 0,
          term: t,
          sourceLang: 'en',
          targetLang: 'uk',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    final svc = BackupService(dict, lib, libDir.path);
    final zip = p.join(tmp.path, 'd.zip');
    await svc.exportTo(zip, includeLibrary: false, includeDictionary: true);

    // Import into a fresh DB twice.
    final db2 = AppDatabase.inMemory();
    final svc2 = BackupService(
      DictionaryRepository(db2),
      LibraryRepository(db2),
      libDir.path,
    );
    final first = await svc2.importFrom(
      zip,
      includeLibrary: false,
      includeDictionary: true,
    );
    expect(first.entries, 3);
    expect(first.skipped, 0);
    final second = await svc2.importFrom(
      zip,
      includeLibrary: false,
      includeDictionary: true,
    );
    expect(second.entries, 0);
    expect(second.skipped, 3);

    db.dispose();
    db2.dispose();
  });

  test('excluding a section leaves it out of the archive', () async {
    final db = AppDatabase.inMemory();
    final libDir = Directory(p.join(tmp.path, 'l2'))..createSync();
    final now = DateTime.now();
    final dict = DictionaryRepository(db);
    dict.insert(
      DictionaryEntry(
        id: 0,
        term: 'x',
        sourceLang: 'en',
        targetLang: 'uk',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final svc = BackupService(dict, LibraryRepository(db), libDir.path);
    final zip = p.join(tmp.path, 'dictonly.zip');
    await svc.exportTo(zip, includeLibrary: false, includeDictionary: true);

    final info = await svc.inspect(zip);
    expect(info.hasLibrary, isFalse);
    expect(info.hasDictionary, isTrue);
    expect(info.dictionaryCount, 1);
    db.dispose();
  });
}
