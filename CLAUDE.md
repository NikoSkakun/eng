# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`eng` is a Flutter desktop/mobile app for reading foreign-language books and
documents (PDF + reflowable formats) with an auto-highlighting vocabulary
dictionary and inline translations. First-class targets: **Linux** and **iOS**
(macOS desktop also enabled). Verified with **Flutter 3.44.2 / Dart 3.12**
(SDK `^3.12.2`).

## Commands

```bash
flutter config --enable-native-assets   # ONE-TIME, REQUIRED — pdfrx bundles PDFium via Dart native assets; builds fail confusingly without it
flutter pub get

flutter run -d linux                     # or -d macos / -d ios (iOS needs macOS+Xcode and `cd ios && pod install`)
flutter build linux --release

flutter analyze                          # static analysis / lints (flutter_lints, see analysis_options.yaml)
dart format lib test                     # formatter

flutter test                             # all tests
flutter test test/term_matcher_test.dart # a single file
flutter test --name "sub-word"           # tests whose name matches a substring

BUILD=1 packaging/build_deb.sh 1.1.0     # build Linux release + package a .deb (omit BUILD=1 to reuse an existing bundle)
```

Tests are pure Dart/unit (no device needed) and use `AppDatabase.inMemory()`;
they cover the matcher, normalizer, repositories, and book parsers.

## Architecture

Layered under `lib/src/`, dependencies pointing downward:
`ui` → `state` (Riverpod) → `services` / `data` / `text` → `models`.
`main.dart` is the composition root: it opens the DB, loads prefs, restores
window size, then runs `ProviderScope` **overriding** `appDatabaseProvider`,
`sharedPreferencesProvider`, and `libraryDirectoryProvider` with the real
instances (their default providers throw — see `state/providers.dart`).

### The matching pipeline (the core of the app)

This is the one flow that spans the most files; understand it before touching
highlighting, normalization, or the readers:

1. Dictionary entries live in the SQLite `dictionary` table but **matching is
   in-memory** — SQLite is persistence only.
2. `DictionaryController` (`state/dictionary_controller.dart`) holds every entry
   in a `DictionaryState` snapshot carrying a `revision` counter that increments
   on every change.
3. `matchableTermsFor(documentId, learningLang)` filters entries to those that
   are highlight-enabled, in scope (global, or scoped to this document), and in
   the document's `learningLang`, producing `List<MatchableTerm>`.
4. A `TermMatcher` (`text/term_matcher.dart`) is built from those terms. It
   matches on **word boundaries** (so "cat" doesn't light up inside "category"),
   indexed by first word; it also supports multi-word phrases (longest wins) and
   per-entry **partial/sub-word** single-word terms.
5. The reader runs `findMatches(pageText)` → `List<TermMatch>`, each a half-open
   `[start, end)` range of **code-unit indices** into the page text.
6. Those ranges are mapped onto pdfrx's per-character rectangles (`charRects`) to
   paint highlight overlays and inline glosses on a canvas.

**Critical invariant:** `TextNormalizer.normalizeToken` must stay **1:1 per code
unit** (only case-fold and unify hyphen/apostrophe variants). The matcher
normalizes tokens of the *original* page text, so `TermMatch` offsets must still
index into both the raw string and `charRects`. Do **not** add diacritic
stripping, ligature expansion, or any length-changing transform there — it would
desync highlights from the rendered glyphs. (`normalizeKey`, used only for
dedup/lookup, is free to collapse whitespace and is *not* offset-sensitive.)

**Live updates / stale-compute guard:** the reader watches `DictionaryState.revision`
to rebuild its matcher when the dictionary or language changes. Page text loads
asynchronously, so the reader also tracks a `_matcherGeneration`; an in-flight
per-page compute checks it on completion and discards results computed against a
now-replaced matcher.

### Two readers, one highlighting model

`DocumentFormat` (`models/document_format.dart`) splits documents in two:
- **PDF** → `ui/reader/reader_screen.dart` — fixed layout via pdfrx/PDFium, char
  rects, in-document search.
- **Everything reflowable** (EPUB, MOBI/AZW/PRC, FB2, TXT, HTML, Markdown, RTF)
  → `ui/reader/text_reader_screen.dart` — flowing text.

Both share the same matcher, translation popup, and add-entry sheet. Every
reflowable parser (`services/book/`) normalizes its format into one shape —
`BookContent` (a list of `BookBlock` paragraphs/headings) — so the text reader
only understands `BookContent`. Parsing runs on a **background isolate** via
`compute()` in `book_loader.dart` (the dispatch point by format).

### Translation / definitions

`services/translation/translation_service.dart` orchestrates pluggable providers.
Translation tries the configured provider, then falls back to keyless **MyMemory**;
definitions fall back to **Wiktionary**. Results are cached in the SQLite `cache`
table under **provider-namespaced keys** (switching providers re-queries), with
TTL'd negative caching for "no definition found". The service holds an immutable
settings snapshot and is **recreated whenever settings change**
(`translationServiceProvider` watches `settingsControllerProvider`).

### Cross-library contexts (usages)

A term's occurrences across the whole library are cached persistently in the
`usages` / `usage_index` tables (schema v6). `WordContextsService`
(`services/contexts/`) extracts each document's text once per session (PDF via
`PdfDocument.openFile`→`loadStructuredText`, books via `loadBook`) and matches
the term with `TermMatcher`; `UsageIndexer` drives this on a **single serial
background queue** — the document being read first, then the rest of the library
— writing occurrence **pointers** (PDF page / book block index + a snippet).
The Dictionary's contexts screen reads straight from the cache (instant) and
tapping a context jumps to the source via `ReaderScreen.initialPage` /
`TextReaderScreen.initialBlockIndex`. Indexing is triggered on term add/edit
(`add_entry_sheet`, current doc prioritized), document import
(`LibraryController`), and on opening the contexts screen (fills gaps —
resumable). Cascades drop a term's/document's usages automatically (FKs).

### Persistence

All app data lives in the OS app-support dir: `eng.db` (SQLite, WAL,
foreign-keys ON) plus a `library/` folder holding **copies** of imported files.
Settings and window size go through `shared_preferences`.

The schema is **hand-written SQL with manual migrations** in
`data/app_database.dart` — `sqlite3` is used directly, **no ORM or codegen**
(the `drift_dev` / `build_runner` dev-dependencies are vestigial and unused: no
`.g.dart`, no `part`, no build step). Repositories in `data/` wrap raw queries.

## Conventions & touch points

- **Commits:** Conventional Commits with a scope — `feat(reader):`, `fix(library):`,
  `perf(reader):`, `build:`.
- **Adding a DB column/table:** bump `AppDatabase.schemaVersion`, add an
  incremental `if (version == N)` branch in `_migrate`, and add the column to the
  `version == 0` fresh-install block so new installs match migrated ones.
- **Adding a setting:** add the field + default to `AppSettings`, extend
  `copyWith`, add a `_k…` key constant, and read/write it in both `load()` and
  `save()` (all in `data/settings_store.dart` — note the settings *model* lives
  in the data layer alongside its store).
- **Adding a translation/definition provider:** implement the interface in
  `services/translation/providers/`, add an enum id in `settings_store.dart`, and
  wire it into the `switch` in `translation_service.dart`.
- **Adding a book format:** extend the `DocumentFormat` enum, `documentFormatForPath`,
  and `kSupportedImportExtensions` (`models/document_format.dart`), then add a
  parser and a `case` in `book_loader.dart`.
- State is **Riverpod**; mutations go through the `Notifier` controllers
  (`Dictionary`/`Library`/`Settings`Controller), never the repositories directly
  from the UI, so `revision`/state updates fire.
