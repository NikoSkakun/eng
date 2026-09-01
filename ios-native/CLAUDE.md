# CLAUDE.md

Guidance for Claude Code working in this repo.

`eng-ios` is a native **SwiftUI + PDFKit** iPhone app: a **PDF-only** port of the
Flutter app at `../eng` — a foreign-language reader with an auto-highlighting
vocabulary dictionary and inline translations. Min deployment target **iOS 17.0**.

## Build / iterate

The dev Mac is **Xcode 15.4 / macOS 14.3, no Homebrew**, so there is **no
`.xcodeproj`** — the app builds with a single `swiftc` invocation over every file
in `Eng/` (a SwiftUI `@main` app, no storyboard, no external packages — system
frameworks only, including `import SQLite3`).

```bash
# fast type-check of the whole module
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun -sdk iphoneos swiftc -typecheck -swift-version 5 -target arm64-apple-ios17.0 -sdk "$SDK" $(find Eng -name '*.swift')

tools/ota/build_ipa.sh          # build .app (+ signed .ipa if SIGN_IDENTITY/PROFILE set)
tools/ota/deploy-ota.sh         # mint ad-hoc profile → build signed IPA → tailscale serve → print install URL
tools/ota/deploy-ota.sh --stop  # stop serving
```

Do **not** add Swift Package Manager dependencies — the `swiftc` build compiles a
single module with no package resolution. Use system frameworks (SwiftUI,
PDFKit, `SQLite3`, Foundation, UIKit) only.

## Architecture

Layered, dependencies pointing down: `UI` → `Store` (`AppState`) →
`Services`/`Data`/`Text` → `Models`.

- **`AppState`** (`Store/AppState.swift`) is the single `@MainActor
  ObservableObject` (the Riverpod analog): holds `settings`, `entries`,
  `documents`, and a `dictionaryRevision` counter the reader watches to rebuild
  its matcher. All mutations go through it.
- **The matching engine** (`Text/`) is a faithful port and the core of the app.
  `TermMatcher` indexes terms by first word, matches on word boundaries
  (longest phrase wins), and supports per-entry partial sub-word matching.

### Critical invariant (do not break)

`TextNormalizer.normalizeToken` must stay **1:1 per UTF-16 code unit** (only
case-fold + unify apostrophe/hyphen variants). Match offsets (`TermMatch.start/end`)
are UTF-16 code-unit indices, handed directly to `PDFPage.selection(for: NSRange)`
and `characterIndex(at:)`. Any length-changing transform (diacritic stripping,
ligature expansion) would desync highlights from the rendered glyphs. `normalizeKey`
(dedup/lookup only) is free to collapse whitespace.

### Reader (`UI/Reader/ReaderView.swift`)

`ReaderCoordinator` owns the `PDFView`, computes `findMatches` per page (lazy,
cached by page index), turns each match into a `PDFSelection`, and paints them
via `pdfView.highlightedSelections` (non-destructive). A tap gesture hit-tests
`characterIndex(at:)` → the most specific covering match → opens the popup;
`PDFViewSelectionChanged` surfaces the current selection for the **Add** sheet.
Rebuild happens on `AppState.dictionaryRevision` changes.

### Persistence

`Data/Database.swift` wraps `SQLite3` directly (no ORM). Schema v2: `documents`
(incl. `view_matrix` — the exact saved view as `DocumentViewState` JSON),
`dictionary`, `cache`. Adding a column: bump `schemaVersion`, add an incremental
`if version == N` branch in `migrate()`, AND add the column to the fresh-install
`version == 0` block. Imported PDFs are copied into the app-support `library/`
folder; the DB stores the file **name** (not an absolute path) so it survives the
container path changing between installs.

## OTA deploy specifics

- Signs `com.coloristique.eng` against team **GH6HRY4EWZ**'s **wildcard App ID**
  (`*`) with an **ad-hoc** profile (`tools/ota/mint_ota_profile.py`), scoped to
  the owner's iPhone by default. No new App ID is registered.
- Reuses `../../dev/namapi` tooling via `NAMAPI_TOOLS`: `secrets.env` (ASC key +
  dist `.p12`) and `setup_signing.sh` (keychain import + partition list).
- Transport is `tailscale serve` (this Mac = `air.tailb321be.ts.net`). Running a
  deploy **takes over** the Mac's single `tailscale serve` slot (namapi uses the
  same). Loopback server on port **8477**.
- Full rationale (Xcode-15 / no-Homebrew constraints, why ad-hoc, why swiftc) is
  in `../../dev/namapi/tools/remote-deploy/OTA-LOCAL-XCODE15.md`.

## Conventions

- Commits: Conventional Commits (`feat(reader):`, `fix(matcher):`).
- Keep the port faithful to `../eng`'s engine; when in doubt, read the Dart
  source under `../eng/lib/src/{text,models,data,services}`.
