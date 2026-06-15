import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../data/dictionary_repository.dart';
import '../data/library_repository.dart';
import '../models/dictionary_entry.dart';
import '../models/library_document.dart';
import '../text/text_normalizer.dart';

/// Outcome of an export/import operation.
class BackupResult {
  const BackupResult({this.documents = 0, this.entries = 0, this.skipped = 0});

  final int documents;
  final int entries;

  /// Dictionary entries skipped on import because an identical term already
  /// existed in the same scope.
  final int skipped;
}

/// What a backup file contains (used to pre-fill the import dialog).
class BackupContents {
  const BackupContents({
    required this.hasLibrary,
    required this.hasDictionary,
    required this.documentCount,
    required this.dictionaryCount,
  });

  final bool hasLibrary;
  final bool hasDictionary;
  final int documentCount;
  final int dictionaryCount;
}

/// Exports/imports the user's data as a single portable `.zip`:
/// a `manifest.json` (dictionary entries + document metadata) plus the actual
/// PDF files, so the library can be restored on another device.
class BackupService {
  BackupService(this._dictionary, this._library, this._libraryDir);

  final DictionaryRepository _dictionary;
  final LibraryRepository _library;
  final String _libraryDir;

  static const int formatVersion = 1;
  static const String _manifestName = 'manifest.json';

  /// Write a backup zip to [destPath].
  Future<BackupResult> exportTo(
    String destPath, {
    required bool includeLibrary,
    required bool includeDictionary,
  }) async {
    final archive = Archive();
    final manifest = <String, Object?>{
      'app': 'eng',
      'formatVersion': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
    };

    var docCount = 0;
    var entryCount = 0;

    if (includeLibrary) {
      final docs = _library.getAll();
      final docList = <Map<String, Object?>>[];
      for (final d in docs) {
        final file = File(d.filePath);
        if (!file.existsSync()) continue; // file went missing; skip it
        final bytes = await file.readAsBytes();
        final archiveName = 'files/${d.id}_${p.basename(d.filePath)}';
        archive.addFile(ArchiveFile.bytes(archiveName, bytes));
        docList.add({
          'id': d.id,
          'title': d.title,
          'pageCount': d.pageCount,
          'lastPage': d.lastPage,
          'addedAt': d.addedAt.millisecondsSinceEpoch,
          'lastOpenedAt': d.lastOpenedAt?.millisecondsSinceEpoch,
          'file': archiveName,
        });
        docCount++;
      }
      manifest['documents'] = docList;
    }

    if (includeDictionary) {
      final entries = _dictionary.getAll();
      manifest['dictionary'] = [
        for (final e in entries)
          {
            'term': e.term,
            'sourceLang': e.sourceLang,
            'targetLang': e.targetLang,
            'translation': e.translation,
            'definition': e.definition,
            'notes': e.notes,
            'highlightEnabled': e.highlightEnabled,
            'colorValue': e.colorValue,
            'scopeDocumentId': e.scopeDocumentId,
            'createdAt': e.createdAt.millisecondsSinceEpoch,
            'updatedAt': e.updatedAt.millisecondsSinceEpoch,
          },
      ];
      entryCount = entries.length;
    }

    archive.addFile(
      ArchiveFile.string(
        _manifestName,
        const JsonEncoder.withIndent('  ').convert(manifest),
      ),
    );

    final zipBytes = ZipEncoder().encodeBytes(archive);
    await File(destPath).writeAsBytes(zipBytes);
    return BackupResult(documents: docCount, entries: entryCount);
  }

  /// Read just the manifest to learn what a backup file contains.
  Future<BackupContents> inspect(String srcPath) async {
    final manifest = await _readManifest(srcPath);
    final docs = manifest['documents'];
    final dict = manifest['dictionary'];
    return BackupContents(
      hasLibrary: docs is List,
      hasDictionary: dict is List,
      documentCount: docs is List ? docs.length : 0,
      dictionaryCount: dict is List ? dict.length : 0,
    );
  }

  /// Restore from a backup zip. Library PDFs are copied into the library dir;
  /// document-scoped dictionary entries are remapped to the new document ids,
  /// and entries that already exist (same term + scope) are skipped.
  Future<BackupResult> importFrom(
    String srcPath, {
    required bool includeLibrary,
    required bool includeDictionary,
  }) async {
    final bytes = await File(srcPath).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('This file is not a valid backup archive.');
    }
    final manifestFile = archive.findFile(_manifestName);
    if (manifestFile == null) {
      throw const FormatException('Backup is missing its manifest.');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestFile.readBytes()!))
            as Map<String, Object?>;

    var docCount = 0;
    var entryCount = 0;
    var skipped = 0;
    final idMap = <int, int>{}; // original doc id -> new doc id

    if (includeLibrary && manifest['documents'] is List) {
      for (final raw in manifest['documents'] as List) {
        if (raw is! Map) continue;
        final m = raw.cast<String, Object?>();
        final archiveName = m['file'] as String?;
        if (archiveName == null) continue;
        final fileBytes = archive.findFile(archiveName)?.readBytes();
        if (fileBytes == null) continue;

        final base = p.basename(archiveName).replaceFirst(RegExp(r'^\d+_'), '');
        var dest = p.join(_libraryDir, base);
        var i = 1;
        while (File(dest).existsSync()) {
          dest = p.join(
            _libraryDir,
            '${p.basenameWithoutExtension(base)} ($i)${p.extension(base)}',
          );
          i++;
        }
        await File(dest).writeAsBytes(fileBytes);

        final saved = _library.insert(
          LibraryDocument(
            id: 0,
            title: (m['title'] as String?) ?? base,
            filePath: dest,
            pageCount: (m['pageCount'] as num?)?.toInt() ?? 0,
            lastPage: (m['lastPage'] as num?)?.toInt() ?? 1,
            addedAt: _date(m['addedAt']) ?? DateTime.now(),
            lastOpenedAt: _date(m['lastOpenedAt']),
          ),
        );
        final oldId = (m['id'] as num?)?.toInt();
        if (oldId != null) idMap[oldId] = saved.id;
        docCount++;
      }
    }

    if (includeDictionary && manifest['dictionary'] is List) {
      for (final raw in manifest['dictionary'] as List) {
        if (raw is! Map) continue;
        final m = raw.cast<String, Object?>();
        final term = (m['term'] as String?)?.trim();
        if (term == null || term.isEmpty) continue;

        // Remap a document-scoped entry to the freshly imported document; if
        // that document wasn't imported, fall back to a global entry.
        var scope = (m['scopeDocumentId'] as num?)?.toInt();
        if (scope != null) scope = idMap[scope];

        final existing = _dictionary.findByNormalized(
          TextNormalizer.normalizeKey(term),
          scopeDocumentId: scope,
        );
        if (existing != null) {
          skipped++;
          continue;
        }

        final now = DateTime.now();
        _dictionary.insert(
          DictionaryEntry(
            id: 0,
            term: term,
            sourceLang: (m['sourceLang'] as String?) ?? 'en',
            targetLang: (m['targetLang'] as String?) ?? 'uk',
            translation: m['translation'] as String?,
            definition: m['definition'] as String?,
            notes: m['notes'] as String?,
            highlightEnabled: (m['highlightEnabled'] as bool?) ?? true,
            colorValue: (m['colorValue'] as num?)?.toInt(),
            scopeDocumentId: scope,
            createdAt: _date(m['createdAt']) ?? now,
            updatedAt: _date(m['updatedAt']) ?? now,
          ),
        );
        entryCount++;
      }
    }

    return BackupResult(
      documents: docCount,
      entries: entryCount,
      skipped: skipped,
    );
  }

  Future<Map<String, Object?>> _readManifest(String srcPath) async {
    final bytes = await File(srcPath).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('This file is not a valid backup archive.');
    }
    final manifestFile = archive.findFile(_manifestName);
    if (manifestFile == null) {
      throw const FormatException('Backup is missing its manifest.');
    }
    return jsonDecode(utf8.decode(manifestFile.readBytes()!))
        as Map<String, Object?>;
  }

  static DateTime? _date(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
}
