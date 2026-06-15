import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';

/// A tiny string key/value cache backed by the `cache` table.
///
/// Used to memoize translation and definition lookups so we respect the free
/// APIs' rate limits and so previously looked-up words keep working offline.
class CacheRepository {
  CacheRepository(this._appDb);

  final AppDatabase _appDb;
  Database get _db => _appDb.db;

  String? get(String key) {
    final rows = _db.select(
      'SELECT value FROM cache WHERE cache_key = ? LIMIT 1;',
      [key],
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  void put(String key, String value) {
    _db.execute(
      '''
      INSERT INTO cache(cache_key, value, created_at) VALUES(?,?,?)
      ON CONFLICT(cache_key) DO UPDATE SET value = excluded.value, created_at = excluded.created_at;
      ''',
      [key, value, DateTime.now().millisecondsSinceEpoch],
    );
  }

  void clear() => _db.execute('DELETE FROM cache;');
}
