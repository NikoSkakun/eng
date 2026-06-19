import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../models/usage.dart';
import 'app_database.dart';

/// Persistence for the cross-library "usages" cache (see [AppDatabase]).
class UsageRepository {
  UsageRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  /// All cached usages for a term, ordered by document then in-document order.
  List<Usage> forEntry(int entryId) {
    final rows = _db.select(
      'SELECT * FROM usages WHERE entry_id = ? ORDER BY document_id, ord, id;',
      [entryId],
    );
    return rows.map(_fromRow).toList();
  }

  /// Document ids already scanned for [entryId] (whether or not they had hits).
  Set<int> indexedDocsForEntry(int entryId) {
    final rows = _db.select(
      'SELECT document_id FROM usage_index WHERE entry_id = ?;',
      [entryId],
    );
    return {for (final r in rows) r['document_id'] as int};
  }

  bool isIndexed(int entryId, int documentId) => _db
      .select(
        'SELECT 1 FROM usage_index WHERE entry_id = ? AND document_id = ? LIMIT 1;',
        [entryId, documentId],
      )
      .isNotEmpty;

  int countForEntry(int entryId) =>
      _db.select('SELECT COUNT(*) AS c FROM usages WHERE entry_id = ?;', [
        entryId,
      ]).first['c'] as int;

  /// Replace the cached usages for one (entry, document) pair and mark the pair
  /// scanned. Atomic, so a partially-written pair is never observed.
  void putPair(int entryId, int documentId, List<Usage> usages) {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute(
        'DELETE FROM usages WHERE entry_id = ? AND document_id = ?;',
        [entryId, documentId],
      );
      for (var i = 0; i < usages.length; i++) {
        final u = usages[i];
        _db.execute(
          'INSERT INTO usages(entry_id, document_id, page, block_index, snippet, hl_ranges, ord) '
          'VALUES(?,?,?,?,?,?,?);',
          [
            entryId,
            documentId,
            u.page,
            u.blockIndex,
            u.snippet,
            jsonEncode([for (final h in u.highlights) [h.start, h.end]]),
            i,
          ],
        );
      }
      _db.execute(
        'INSERT OR REPLACE INTO usage_index(entry_id, document_id) VALUES(?,?);',
        [entryId, documentId],
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Forget everything cached for an entry (its usages and scanned-pair marks),
  /// e.g. before re-indexing because its term or match mode changed.
  void clearEntry(int entryId) {
    _db.execute('DELETE FROM usages WHERE entry_id = ?;', [entryId]);
    _db.execute('DELETE FROM usage_index WHERE entry_id = ?;', [entryId]);
  }

  Usage _fromRow(Row row) {
    final ranges = jsonDecode(row['hl_ranges'] as String) as List;
    return Usage(
      id: row['id'] as int,
      entryId: row['entry_id'] as int,
      documentId: row['document_id'] as int,
      page: row['page'] as int?,
      blockIndex: row['block_index'] as int?,
      snippet: row['snippet'] as String,
      highlights: [
        for (final r in ranges)
          (start: (r as List)[0] as int, end: r[1] as int),
      ],
    );
  }
}
