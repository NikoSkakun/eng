import 'package:eng/src/data/app_database.dart';
import 'package:eng/src/data/dictionary_repository.dart';
import 'package:eng/src/data/library_repository.dart';
import 'package:eng/src/models/dictionary_entry.dart';
import 'package:eng/src/models/library_document.dart';
import 'package:eng/src/models/library_folder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.inMemory());
  tearDown(() => db.dispose());

  test('schema is created at the current version', () {
    expect(db.db.userVersion, AppDatabase.schemaVersion);
  });

  group('DictionaryRepository', () {
    test('insert assigns an id and stores normalized term', () {
      final repo = DictionaryRepository(db);
      final now = DateTime.now();
      final saved = repo.insert(
        DictionaryEntry(
          id: 0,
          term: 'The  Cat',
          sourceLang: 'en',
          targetLang: 'uk',
          translation: 'кіт',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(saved.id, greaterThan(0));
      expect(saved.normalizedTerm, 'the cat');

      final found = repo.findByNormalized('the cat');
      expect(found, isNotNull);
      expect(found!.translation, 'кіт');
    });

    test('update and delete work', () {
      final repo = DictionaryRepository(db);
      final now = DateTime.now();
      final saved = repo.insert(
        DictionaryEntry(
          id: 0,
          term: 'dog',
          sourceLang: 'en',
          targetLang: 'uk',
          createdAt: now,
          updatedAt: now,
        ),
      );
      repo.update(saved.copyWith(translation: 'пес', highlightEnabled: false));
      final updated = repo.getById(saved.id)!;
      expect(updated.translation, 'пес');
      expect(updated.highlightEnabled, isFalse);

      repo.delete(saved.id);
      expect(repo.getAll(), isEmpty);
    });

    test('persists sub-word matching flag and parent word', () {
      final repo = DictionaryRepository(db);
      final now = DateTime.now();
      final saved = repo.insert(
        DictionaryEntry(
          id: 0,
          term: 'perturbation',
          sourceLang: 'en',
          targetLang: 'uk',
          matchPartial: true,
          sourceWord: 'perturbations',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final got = repo.getById(saved.id)!;
      expect(got.matchPartial, isTrue);
      expect(got.sourceWord, 'perturbations');

      repo.update(got.copyWith(matchPartial: false, sourceWord: null));
      final updated = repo.getById(saved.id)!;
      expect(updated.matchPartial, isFalse);
      expect(updated.sourceWord, isNull);
    });

    test('persists and updates alternative translations', () {
      final repo = DictionaryRepository(db);
      final now = DateTime.now();
      final saved = repo.insert(
        DictionaryEntry(
          id: 0,
          term: 'chat',
          sourceLang: 'fr',
          targetLang: 'en',
          translation: 'cat',
          alternativeTranslations: const ['tomcat', 'pussycat'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      final got = repo.getById(saved.id)!;
      expect(got.translation, 'cat');
      expect(got.alternativeTranslations, ['tomcat', 'pussycat']);
      expect(got.hasMultipleTranslations, isTrue);
      expect(got.allTranslations, ['cat', 'tomcat', 'pussycat']);

      // Clearing alternatives round-trips to an empty list (column stored NULL).
      repo.update(got.copyWith(alternativeTranslations: const []));
      final cleared = repo.getById(saved.id)!;
      expect(cleared.alternativeTranslations, isEmpty);
      expect(cleared.hasMultipleTranslations, isFalse);
    });

    test('scoped lookup distinguishes global vs document entries', () {
      final repo = DictionaryRepository(db);
      final now = DateTime.now();
      repo.insert(
        DictionaryEntry(
          id: 0,
          term: 'run',
          sourceLang: 'en',
          targetLang: 'uk',
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(repo.findByNormalized('run'), isNotNull);
      expect(repo.findByNormalized('run', scopeDocumentId: 1), isNull);
    });
  });

  group('DictionaryEntry translations', () {
    DictionaryEntry make({String? translation, List<String> alts = const []}) =>
        DictionaryEntry(
          id: 0,
          term: 't',
          sourceLang: 'en',
          targetLang: 'uk',
          translation: translation,
          alternativeTranslations: alts,
          createdAt: DateTime(2020),
          updatedAt: DateTime(2020),
        );

    test(
      'allTranslations is primary-first and de-dupes case-insensitively',
      () {
        final e = make(
          translation: 'Cat',
          alts: const ['cat', 'Tomcat', 'tomcat', '   '],
        );
        expect(e.allTranslations, ['Cat', 'Tomcat']);
        expect(e.hasMultipleTranslations, isTrue);
        expect(e.glossText, 'Cat');
      },
    );

    test('a single translation is not marked as multi-variant', () {
      final e = make(translation: 'cat');
      expect(e.hasMultipleTranslations, isFalse);
      expect(e.allTranslations, ['cat']);
      expect(e.glossText, 'cat');
    });

    test('falls back to alternatives when no primary is set', () {
      final e = make(translation: null, alts: const ['x', 'y']);
      expect(e.glossText, 'x');
      expect(e.allTranslations, ['x', 'y']);
      expect(e.hasContent, isTrue);
    });

    test('no translations means no content and no gloss', () {
      final e = make();
      expect(e.allTranslations, isEmpty);
      expect(e.glossText, isNull);
      expect(e.hasMultipleTranslations, isFalse);
      expect(e.hasContent, isFalse);
    });
  });

  group('LibraryRepository', () {
    test('CRUD round-trips a document', () {
      final repo = LibraryRepository(db);
      final saved = repo.insert(
        LibraryDocument(
          id: 0,
          title: 'Sample',
          filePath: '/tmp/sample.pdf',
          addedAt: DateTime.now(),
        ),
      );
      expect(saved.id, greaterThan(0));

      expect(saved.viewMatrix, isNull);
      repo.update(
        saved.copyWith(lastPage: 5, pageCount: 42, viewMatrix: '1.0,0.0,2.5'),
      );
      final got = repo.getById(saved.id)!;
      expect(got.lastPage, 5);
      expect(got.pageCount, 42);
      expect(got.viewMatrix, '1.0,0.0,2.5'); // exact scroll/zoom persists

      repo.delete(saved.id);
      expect(repo.getAll(), isEmpty);
    });

    test('folders: CRUD and filing documents', () {
      final repo = LibraryRepository(db);
      final now = DateTime.now();
      final folder = repo.insertFolder(
        LibraryFolder(id: 0, name: 'Aerodynamics', createdAt: now),
      );
      expect(folder.id, greaterThan(0));
      expect(repo.getAllFolders().single.name, 'Aerodynamics');

      final doc = repo.insert(
        LibraryDocument(
          id: 0,
          title: 'Paper',
          filePath: '/tmp/p.pdf',
          addedAt: now,
        ),
      );
      expect(doc.folderId, isNull);

      repo.setDocumentFolder(doc.id, folder.id);
      expect(repo.getById(doc.id)!.folderId, folder.id);

      repo.renameFolder(folder.id, 'Aero');
      expect(repo.getAllFolders().single.name, 'Aero');

      // Deleting a folder keeps its documents but moves them back to the root.
      repo.deleteFolder(folder.id);
      expect(repo.getAllFolders(), isEmpty);
      final after = repo.getById(doc.id)!;
      expect(after, isNotNull);
      expect(after.folderId, isNull);
    });

    test('nested folders and positions round-trip', () {
      final repo = LibraryRepository(db);
      final now = DateTime.now();
      final parent = repo.insertFolder(
        LibraryFolder(id: 0, name: 'Parent', createdAt: now, position: 0),
      );
      final child = repo.insertFolder(
        LibraryFolder(
          id: 0,
          name: 'Child',
          createdAt: now,
          parentId: parent.id,
          position: 3,
        ),
      );
      final got = repo.getAllFolders().firstWhere((f) => f.id == child.id);
      expect(got.parentId, parent.id);
      expect(got.position, 3);

      repo.setFolderParent(child.id, null, position: 1);
      final moved = repo.getAllFolders().firstWhere((f) => f.id == child.id);
      expect(moved.parentId, isNull);
      expect(moved.position, 1);
    });

    test('deleting a document cascades to its scoped dictionary entries', () {
      final libRepo = LibraryRepository(db);
      final dictRepo = DictionaryRepository(db);
      final now = DateTime.now();
      final doc = libRepo.insert(
        LibraryDocument(
          id: 0,
          title: 'Doc',
          filePath: '/tmp/doc.pdf',
          addedAt: now,
        ),
      );
      dictRepo.insert(
        DictionaryEntry(
          id: 0,
          term: 'scoped',
          sourceLang: 'en',
          targetLang: 'uk',
          scopeDocumentId: doc.id,
          createdAt: now,
          updatedAt: now,
        ),
      );
      expect(dictRepo.getAll().length, 1);
      libRepo.delete(doc.id);
      expect(dictRepo.getAll(), isEmpty);
    });
  });
}
