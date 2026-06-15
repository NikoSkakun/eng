# eng — foreign-language PDF reader

Read PDFs in a language you're learning. Select an unknown word or phrase, give
it a translation/definition, and the app **auto-highlights every occurrence** of
that term — across the whole document and, by default, across your entire
library. Hover (desktop) or tap (mobile) a highlight to see its
translation/definition in a popup. When you add a new word, the app **suggests a
translation** from free online sources, but always leaves room for your own
wording.

Built with Flutter; first-class targets are **Linux (Ubuntu)** and **iOS**
(macOS desktop is also enabled for convenience).

> Defaults are tuned for a Ukrainian speaker learning English (English →
> Ukrainian), but the language pair and providers are configurable in Settings.

## Features

- 📚 **Library** — import PDFs (copied into an app-managed folder), reopen at
  your last page.
- ✍️ **Add terms while reading** — select a word/phrase → a sheet opens with an
  auto-suggested translation and an optional dictionary definition; edit freely.
- 🖍️ **Automatic highlighting** — saved terms are matched on **whole words /
  phrases** (so "cat" doesn't light up inside "category") and highlighted
  wherever they appear. Shared across all documents by default; can be scoped to
  a single document per entry.
- 💬 **Popup on hover/tap** — shows the stored translation, definition and notes;
  edit from there.
- 🗂️ **Dictionary manager** — search, edit, delete, toggle highlighting per term.
- ⚙️ **Pluggable providers** — keyless by default, upgradeable to your own keys.

## Tech stack

| Concern | Choice |
|---|---|
| PDF render + text + per-char boxes | [`pdfrx`](https://pub.dev/packages/pdfrx) (PDFium) |
| State management | `flutter_riverpod` |
| Local storage | `sqlite3` (direct, no ORM/codegen) |
| Settings | `shared_preferences` |
| File import | `file_selector` |
| HTTP | `http` |

Architecture: `lib/src/{models,data,services,text,state,ui}`. Dictionary terms
are matched **in memory** by a whole-word/phrase matcher
(`text/term_matcher.dart`); SQLite is only used for persistence, and the matcher
is rebuilt whenever the dictionary changes, so highlights update live.

## Translation & definition providers

Configurable in **Settings**. Nothing requires a paid key by default.

| Provider | Use | Key? |
|---|---|---|
| **MyMemory** (default translation) | EN↔UK and many pairs | none (optional email raises the daily quota) |
| **Free Dictionary API** (default definitions) | English definitions | none |
| **Wiktionary** | definition fallback | none |
| **LibreTranslate** | translation (self-host/mirror) | none if self-hosted |
| **DeepL** | highest-quality translation | your API key |
| **Google (unofficial)** | translation | none, but see warning |

The configured translation provider is tried first, with keyless **MyMemory** as
an automatic fallback. Definitions fall back to Wiktionary. Results are cached
locally (the `cache` table) to respect free quotas and work offline afterwards.

**Privacy:** selected text is sent to the chosen service to fetch suggestions.
Avoid selecting sensitive text, or self-host LibreTranslate for a private setup.

**Attribution:** definitions from the Free Dictionary API / Wiktionary are
licensed **CC BY-SA**; the in-app About section credits the sources.

> The "Google (unofficial)" option uses an undocumented endpoint that may break
> without notice and whose use can violate Google's ToS. It is opt-in only.

---

## Building & running

This repo was scaffolded and verified (analyzer + unit tests) with **Flutter
3.44.2 / Dart 3.12**. Final builds happen on your machine.

`pdfrx` bundles PDFium via **Dart native assets**, which must be enabled:

```bash
flutter config --enable-native-assets
```

### Linux (Ubuntu)

Install the Flutter Linux desktop toolchain (one-time, needs sudo):

```bash
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev libstdc++-12-dev libsqlite3-0
```

Then:

```bash
flutter pub get
flutter run -d linux          # or: flutter build linux
```

### iOS (requires macOS + Xcode)

iOS cannot be built on Linux. On a Mac:

```bash
sudo gem install cocoapods     # if not already installed
flutter pub get
cd ios && pod install && cd ..
flutter run -d ios             # or open ios/Runner.xcworkspace in Xcode
```

Set your signing team in Xcode before running on a device.

### macOS desktop (optional, on a Mac)

```bash
flutter run -d macos
```

## Tests

```bash
flutter test
```

Covers the whole-word/phrase matching engine, text normalization, and the
SQLite repositories (in-memory).

## Known limitations / ideas

- Highlighting depends on the PDF having a real text layer; scanned PDFs without
  OCR won't match. (OCR could be added later.)
- Matching is whole-word; inflected forms (e.g. "run" vs "running") are treated
  as different terms. A lemmatizer could be added.
- Words split by hyphenation across line breaks may not match.
- Tapping a *non-highlighted* word to add it relies on text selection
  (double-tap/drag); direct tap-to-add could be added via the page text index.
- API keys are stored in `shared_preferences` (not an OS keychain); fine for a
  personal app, but consider `flutter_secure_storage` if that matters to you.

## Project layout

```
lib/
  main.dart                      app entry: open DB, load prefs, runApp
  src/
    app.dart                     MaterialApp + theme
    models/                      DictionaryEntry, LibraryDocument
    data/                        sqlite3 database + repositories + settings store
    text/                        normalizer + whole-word/phrase matcher
    services/translation/        provider interfaces + 6 implementations + service
    state/                       Riverpod providers & controllers
    ui/                          home shell, library, reader, dictionary, settings
test/                            matcher + database unit tests
```
