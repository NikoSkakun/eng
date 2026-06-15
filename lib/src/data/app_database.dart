import 'package:sqlite3/sqlite3.dart';

/// Owns the SQLite connection and schema lifecycle.
///
/// We use the `sqlite3` package directly (no ORM/codegen): the schema is tiny,
/// matching runs in memory off the dictionary, and avoiding a build step keeps
/// the project simple and predictable across Linux and iOS. On iOS an
/// up-to-date SQLite is bundled by `sqlite3_flutter_libs`; on Linux the system
/// `libsqlite3` is used.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  /// Bump when the schema changes and add a branch in [_migrate].
  static const int schemaVersion = 2;

  /// Open (creating if needed) the database at [path] and run migrations.
  factory AppDatabase.open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    _migrate(db);
    return AppDatabase._(db);
  }

  /// Open an in-memory database (used by tests).
  factory AppDatabase.inMemory() {
    final db = sqlite3.open(':memory:');
    db.execute('PRAGMA foreign_keys = ON;');
    _migrate(db);
    return AppDatabase._(db);
  }

  static void _migrate(Database db) {
    var version = db.userVersion;
    if (version >= schemaVersion) return;
    if (version == 0) {
      db.execute('''
        CREATE TABLE documents(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          file_path TEXT NOT NULL,
          original_path TEXT,
          page_count INTEGER NOT NULL DEFAULT 0,
          added_at INTEGER NOT NULL,
          last_opened_at INTEGER,
          last_page INTEGER NOT NULL DEFAULT 1,
          view_matrix TEXT
        );
      ''');
      db.execute('''
        CREATE TABLE dictionary(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          term TEXT NOT NULL,
          normalized_term TEXT NOT NULL,
          source_lang TEXT NOT NULL,
          target_lang TEXT NOT NULL,
          translation TEXT,
          definition TEXT,
          notes TEXT,
          highlight_enabled INTEGER NOT NULL DEFAULT 1,
          color_value INTEGER,
          scope_document_id INTEGER REFERENCES documents(id) ON DELETE CASCADE,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      db.execute(
        'CREATE INDEX idx_dictionary_normalized ON dictionary(normalized_term);',
      );
      db.execute(
        'CREATE INDEX idx_dictionary_scope ON dictionary(scope_document_id);',
      );
      db.execute('''
        CREATE TABLE cache(
          cache_key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');
      // Fresh install already includes every column up to the latest version.
      version = schemaVersion;
    }
    if (version == 1) {
      // v1 -> v2: per-document saved view (exact scroll position + zoom).
      db.execute('ALTER TABLE documents ADD COLUMN view_matrix TEXT;');
      version = 2;
    }
    db.userVersion = schemaVersion;
  }

  void dispose() => db.close();
}
