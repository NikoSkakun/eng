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
  static const int schemaVersion = 7;

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
        CREATE TABLE folders(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          parent_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
          position INTEGER NOT NULL DEFAULT 0
        );
      ''');
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
          view_matrix TEXT,
          folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL,
          position INTEGER NOT NULL DEFAULT 0
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
          match_partial INTEGER NOT NULL DEFAULT 0,
          source_word TEXT,
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
      _createUsageTables(db);
      // Fresh install already includes every column up to the latest version.
      version = schemaVersion;
    }
    if (version == 1) {
      // v1 -> v2: per-document saved view (exact scroll position + zoom).
      db.execute('ALTER TABLE documents ADD COLUMN view_matrix TEXT;');
      version = 2;
    }
    if (version == 2) {
      // v2 -> v3: per-entry sub-word matching + remembered parent word.
      db.execute(
        'ALTER TABLE dictionary ADD COLUMN match_partial INTEGER NOT NULL DEFAULT 0;',
      );
      db.execute('ALTER TABLE dictionary ADD COLUMN source_word TEXT;');
      version = 3;
    }
    if (version == 3) {
      // v3 -> v4: group documents into folders. (IF NOT EXISTS guards against a
      // migration that was interrupted after creating the table.)
      db.execute('''
        CREATE TABLE IF NOT EXISTS folders(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');
      db.execute(
        'ALTER TABLE documents ADD COLUMN folder_id INTEGER '
        'REFERENCES folders(id) ON DELETE SET NULL;',
      );
      version = 4;
    }
    if (version == 4) {
      // v4 -> v5: nested folders + manual ordering of library items.
      db.execute(
        'ALTER TABLE folders ADD COLUMN parent_id INTEGER '
        'REFERENCES folders(id) ON DELETE SET NULL;',
      );
      db.execute(
        'ALTER TABLE folders ADD COLUMN position INTEGER NOT NULL DEFAULT 0;',
      );
      db.execute(
        'ALTER TABLE documents ADD COLUMN position INTEGER NOT NULL DEFAULT 0;',
      );
      version = 5;
    }
    if (version == 5) {
      // v5 -> v6: cross-library "usages" cache — occurrence pointers per term,
      // filled in the background so opening a word's contexts is instant.
      _createUsageTables(db);
      version = 6;
    }
    if (version == 6) {
      // v6 -> v7: the first usage indexer discarded a whole PDF's results when a
      // single page failed to extract, so a large book showed no usages for any
      // word. Clear the cache so it rebuilds with the now per-page-resilient
      // extractor.
      db.execute('DELETE FROM usages;');
      db.execute('DELETE FROM usage_index;');
      version = 7;
    }
    db.userVersion = schemaVersion;
  }

  /// Cache of where each dictionary term occurs across the library. [usages]
  /// holds one display-ready snippet per occurrence (with a jump pointer —
  /// [page] for PDFs, [block_index] for reflowable books); [usage_index] records
  /// which (term, document) pairs have been scanned (even when they had no
  /// hits), so indexing is resumable and never redoes work. Both cascade-delete
  /// with their dictionary entry / document.
  static void _createUsageTables(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS usages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL REFERENCES dictionary(id) ON DELETE CASCADE,
        document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        page INTEGER,
        block_index INTEGER,
        snippet TEXT NOT NULL,
        hl_ranges TEXT NOT NULL,
        ord INTEGER NOT NULL DEFAULT 0
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_usages_entry ON usages(entry_id);');
    db.execute('CREATE INDEX IF NOT EXISTS idx_usages_doc ON usages(document_id);');
    db.execute('''
      CREATE TABLE IF NOT EXISTS usage_index(
        entry_id INTEGER NOT NULL REFERENCES dictionary(id) ON DELETE CASCADE,
        document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
        PRIMARY KEY(entry_id, document_id)
      );
    ''');
  }

  void dispose() => db.close();
}
