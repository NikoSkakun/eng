import 'package:eng/src/data/app_database.dart';
import 'package:eng/src/data/dictionary_repository.dart';
import 'package:eng/src/data/library_repository.dart';
import 'package:eng/src/models/dictionary_entry.dart';
import 'package:eng/src/models/library_document.dart';
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

      repo.update(saved.copyWith(lastPage: 5, pageCount: 42));
      final got = repo.getById(saved.id)!;
      expect(got.lastPage, 5);
      expect(got.pageCount, 42);

      repo.delete(saved.id);
      expect(repo.getAll(), isEmpty);
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
