# eng (iOS) — native PDF reader with an auto-highlighting vocabulary dictionary

A native **SwiftUI + PDFKit** port of [`eng`](../eng) for iPhone. Read a PDF in a
language you're learning; select an unknown word or phrase, give it a
translation/definition, and the app **auto-highlights every occurrence** across
the document and (by default) your whole library. Tap a highlight for a popup;
manage everything in the Dictionary tab.

This port reads **PDF and EPUB**. PDFs use the page-faithful PDFKit reader; EPUBs
open in a **reflowable text reader** with a customizable reading view (theme,
typeface, size, spacing, margins, justification). The remaining Flutter formats
(MOBI/FB2/TXT/HTML/MD/RTF) are intentionally out of scope.

> Defaults are tuned for a Ukrainian speaker learning English (English →
> Ukrainian); the language pair and providers are configurable in Settings.

## What's here

The **matching engine is a faithful port** of the Flutter app: the Unicode
tokenizer/normalizer (1:1 per UTF-16 code unit, so offsets index straight into
PDFKit's `NSRange`/`characterBounds`) and the whole-word / multi-word-phrase /
partial sub-word matcher. Everything else is native:

| Concern | Choice |
|---|---|
| PDF render, text, char boxes, selection | **PDFKit** (`PDFView`, `highlightedSelections`) |
| UI | **SwiftUI** |
| Persistence | **raw `SQLite3`** (system lib, no ORM — matches the original design) |
| Settings | `UserDefaults` |
| Networking | `URLSession` (async/await) |

No third-party Swift packages — only system frameworks, so the whole app builds
with a single `swiftc` invocation (see below).

### Features (v1 — the core reader loop)

- **Library** — import PDFs (copied into an app-managed folder), reopen at your
  last page, rename/delete.
- **Reader** — PDFKit page view with **live auto-highlighting** of saved terms;
  select text → **Add** sheet with an auto-suggested translation (MyMemory) and,
  for single English words, a definition (Free Dictionary → Wiktionary); **tap a
  highlight** → popup with the translation/definition (edit/delete).
- **Dictionary** — search, edit, delete, toggle highlighting, per-entry
  sub-word matching and per-document scoping.
- **Settings** — language pair, translation provider (MyMemory / Google
  unofficial), definition provider (Free Dictionary / Wiktionary / none),
  MyMemory email, highlight colour.

Translation tries the configured provider then falls back to keyless MyMemory;
definitions fall back to Wiktionary. Results are cached in SQLite
(provider-namespaced keys, TTL'd negative caching).

### Deferred (follow-ups)

DeepL / LibreTranslate providers, cross-library "contexts" (usage index), inline
interlinear glosses, folders, and backup/export.

## Build & deploy (OTA)

This Mac is **Xcode 15.4 / macOS 14.3, no Homebrew**, so the build is a
hand-rolled `swiftc` harness (no `.xcodeproj` needed), mirroring the `namapi`
repo's OTA path. Deployment is an **ad-hoc** install over `tailscale serve`.

```bash
# Build a signed IPA + mint the ad-hoc profile + serve the install page, then
# open the printed https://<host>.ts.net/ URL in Safari on the registered iPhone
# (Tailscale VPN on):
tools/ota/deploy-ota.sh

tools/ota/deploy-ota.sh --skip-build   # re-serve the existing IPA
tools/ota/deploy-ota.sh --status       # show the serve config
tools/ota/deploy-ota.sh --stop         # stop serving

# Just build the .app / .ipa (unsigned if SIGN_IDENTITY/PROFILE unset):
tools/ota/build_ipa.sh
```

Signing reuses the machine's existing `Apple Distribution: … (GH6HRY4EWZ)`
identity and the ASC API key in `namapi/tools/testflight/secrets.env` (via
`NAMAPI_TOOLS`). The bundle id `com.coloristique.eng` is signed against the
team's **wildcard App ID** (`*`), so no new App ID is registered. See
[`tools/ota/`](tools/ota) and the annotated
[namapi OTA doc](../../dev/namapi/tools/remote-deploy/OTA-LOCAL-XCODE15.md).

### Type-check / iterate

```bash
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun -sdk iphoneos swiftc -typecheck -swift-version 5 \
  -target arm64-apple-ios17.0 -sdk "$SDK" $(find Eng -name '*.swift')
```

Minimum deployment target is **iOS 17.0** (`ContentUnavailableView`, the modern
`onChange`, `.snappy`).

## Project layout

```
Eng/
  App.swift                      @main SwiftUI app
  Models/                        DictionaryEntry, LibraryDocument, AppSettings, TranslationModels
  Text/                          TextNormalizer + TermMatcher (the ported engine)
  Data/                          Database (raw SQLite) + repositories + SettingsStore
  Services/                      TranslationService + Providers/ (MyMemory, Google, Free Dictionary, Wiktionary)
  Store/                         AppState (the single ObservableObject source of truth)
  UI/                            RootView, Library/, Reader/, Dictionary/, Settings/
  Assets.xcassets/               AppIcon (single 1024)
tools/ota/                       build_ipa.sh · mint_ota_profile.py · deploy-ota.sh
tools/make_icon.swift            regenerates the app icon
```
