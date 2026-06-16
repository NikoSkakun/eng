import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/settings_store.dart';
import '../../models/dictionary_entry.dart';
import '../../models/library_document.dart';
import '../../state/dictionary_controller.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';
import '../../text/term_matcher.dart';
import '../../text/text_normalizer.dart';
import 'add_entry_sheet.dart';
import 'translation_popup.dart';

/// Reads a single PDF: renders it with pdfrx, highlights dictionary terms via a
/// per-page overlay, shows a translation popup on hover (desktop) or tap
/// (mobile), and lets the reader add a new term from a text selection.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.document});

  final LibraryDocument document;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _controller = PdfViewerController();
  final _stackKey = GlobalKey();

  /// Per-page matched occurrences (page coordinates), computed lazily.
  final Map<int, List<_Occurrence>> _occurrencesByPage = {};
  final Set<int> _loadingPages = {};

  /// Soft cap on cached pages so a long reading session doesn't grow memory
  /// without bound (pages far from the current one are evicted).
  static const int _maxCachedPages = 100;

  /// Per-page count of empty-text extraction attempts (progressive loading).
  final Map<int, int> _emptyTextRetries = {};
  static const int _maxEmptyTextRetries = 6;

  TermMatcher? _matcher;

  /// Incremented whenever the matcher is rebuilt (dictionary/language change),
  /// so in-flight per-page computes started against an old matcher can detect
  /// that they are stale and discard their results.
  int _matcherGeneration = 0;
  int _lastDictRevision = -1;
  String _learningLang = '';

  _PopupModel? _popup;
  Timer? _hideTimer;

  String? _selectedText;
  // When the current selection is a strict part of a single longer word, this
  // holds that parent word (e.g. selecting "perturbation" inside
  // "perturbations") so a new entry can default to sub-word matching.
  String? _selectedSourceWord;
  Timer? _selectionDebounce;
  // Bumped on every selection change so a stale in-flight debounce callback
  // (whose timer was cancelled after it already started awaiting) can detect it
  // is superseded and not overwrite newer selection state.
  int _selectionGeneration = 0;
  Timer? _viewSaveDebounce;

  // In-document text search. Created once the viewer/controller is ready
  // (the searcher's constructor touches the document immediately).
  PdfTextSearcher? _searcher;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchVisible = false;

  // Captured at build time so the pdfrx callbacks (which can fire between our
  // builds, e.g. on scroll) always see the latest values.
  late AppSettings _settings;
  late DictionaryState _dictState;

  // Memoized viewer params. Rebuilding PdfViewerParams (with fresh closures)
  // on every setState makes pdfrx treat params as changed every frame, so we
  // cache it and only rebuild when an input it depends on actually changes.
  PdfViewerParams? _viewerParams;
  bool? _paramsHighlighting;
  bool _paramsHasSearcher = false;
  PdfTextSelectionParams? _textSelectionParams;

  // Cache of laid-out gloss text painters (keyed by text + size); cleared when
  // the gloss style changes. Avoids re-laying out text every paint frame.
  final Map<String, TextPainter> _glossPainters = {};
  String _glossStyleSig = '';

  @override
  void initState() {
    super.initState();
    // Persist the exact view (scroll + zoom) as the user pans/zooms.
    _controller.addListener(_onViewChanged);
    // Handle Find/Escape at the hardware-keyboard level so the shortcut works
    // regardless of which child (PDF viewer, nothing, …) currently has focus.
    // A focus-scoped CallbackShortcuts only fires when a descendant is focused,
    // which is why Ctrl+F was unreliable here.
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _controller.removeListener(_onViewChanged);
    _searcher?.removeListener(_onSearchChanged);
    _searcher?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _hideTimer?.cancel();
    _selectionDebounce?.cancel();
    _viewSaveDebounce?.cancel();
    _disposeGlossPainters();
    super.dispose();
  }

  void _disposeGlossPainters() {
    for (final p in _glossPainters.values) {
      p.dispose();
    }
    _glossPainters.clear();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  /// Global key handler for Find (Ctrl/Cmd+F) and Escape. Returns true only
  /// when it actually handles the event, so normal typing/scrolling is left
  /// untouched. Inactive while a modal route (e.g. the add-entry sheet) is on
  /// top of the reader.
  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final key = event.logicalKey;
    final kb = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.keyF &&
        (kb.isControlPressed || kb.isMetaPressed)) {
      _openSearch();
      return true;
    }
    if (key == LogicalKeyboardKey.escape && _searchVisible) {
      _closeSearch();
      return true;
    }
    return false;
  }

  void _openSearch() {
    if (!_searchVisible) setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searcher?.resetTextSearch();
    _searchController.clear();
    setState(() => _searchVisible = false);
  }

  void _toggleSearch() => _searchVisible ? _closeSearch() : _openSearch();

  void _rebuildMatcher() {
    final terms = ref
        .read(dictionaryControllerProvider.notifier)
        .matchableTermsFor(widget.document.id, _learningLang);
    _matcher = TermMatcher(terms);
    _matcherGeneration++;
    _occurrencesByPage.clear();
    _loadingPages.clear();
    _emptyTextRetries.clear();
  }

  Future<void> _ensurePageComputed(PdfPage page) async {
    final n = page.pageNumber;
    if (_occurrencesByPage.containsKey(n) || _loadingPages.contains(n)) return;
    final matcher = _matcher;
    final gen = _matcherGeneration;
    if (matcher == null || matcher.isEmpty) {
      _occurrencesByPage[n] = const <_Occurrence>[];
      return;
    }
    _loadingPages.add(n);
    List<_Occurrence>? result;
    try {
      final pageText = await page.loadStructuredText();
      if (!mounted || gen != _matcherGeneration) {
        _loadingPages.remove(n);
        return;
      }
      // While a large document is still progressively loading, a page's text
      // can come back empty before it's ready. Don't cache that empty result
      // (which would leave the page permanently un-highlighted) — retry a few
      // times with backoff so highlights appear once the text loads.
      if (pageText.fullText.isEmpty &&
          (_emptyTextRetries[n] ?? 0) < _maxEmptyTextRetries) {
        final attempt = (_emptyTextRetries[n] ?? 0) + 1;
        _emptyTextRetries[n] = attempt;
        _loadingPages.remove(n);
        Future.delayed(Duration(milliseconds: 200 * attempt), () {
          if (mounted &&
              gen == _matcherGeneration &&
              !_occurrencesByPage.containsKey(n)) {
            setState(() {}); // re-invoke the overlay builder → recompute
          }
        });
        return;
      }

      final matches = matcher.findMatches(pageText.fullText);
      final occ = <_Occurrence>[];
      for (final m in matches) {
        try {
          final range = PdfPageTextRange(
            pageText: pageText,
            start: m.start,
            end: m.end,
          );
          final rects = <PdfRect>[];
          for (final b in range.enumerateFragmentBoundingRects()) {
            if (b.bounds.isNotEmpty) rects.add(b.bounds);
          }
          if (rects.isNotEmpty) occ.add(_Occurrence(m.entryId, rects));
        } catch (_) {
          // Skip occurrences whose ranges can't be resolved to rects.
        }
      }
      result = occ;
    } catch (_) {
      result = const <_Occurrence>[];
    }
    // Only the current-generation compute owns the page's slot and repaint.
    if (!mounted || gen != _matcherGeneration) {
      _loadingPages.remove(n);
      return;
    }
    _occurrencesByPage[n] = result;
    _loadingPages.remove(n);
    if (_occurrencesByPage.length > _maxCachedPages) _evictFarPages();
    setState(() {});
  }

  /// Drop cached pages farthest from the *current viewport* page to bound memory
  /// over a long session. Centring on the viewport (not the just-loaded page,
  /// which may be a prefetch far ahead) avoids evicting visible pages and
  /// re-computing them during fast scrolling.
  void _evictFarPages() {
    final current = (_controller.isReady ? _controller.pageNumber : null) ?? 1;
    final keys = _occurrencesByPage.keys.toList()
      ..sort((a, b) => (b - current).abs().compareTo((a - current).abs()));
    for (final k in keys) {
      if (_occurrencesByPage.length <= _maxCachedPages) break;
      if ((k - current).abs() <= 5) continue; // keep nearby pages
      _occurrencesByPage.remove(k);
      _emptyTextRetries.remove(k);
    }
  }

  /// Map a PDF-space rect (bottom-left origin) to the page overlay's
  /// Flutter-space rect. pdfrx's [PdfRectExt.toRect] handles the Y-flip,
  /// page rotation and uniform scaling correctly; the overlay Stack is sized
  /// to [pageRect], so the page-local result lines up with the highlights.
  Rect _mapRect(PdfRect pr, Rect pageRect, PdfPage page) =>
      pr.toRect(page: page, scaledPageSize: pageRect.size);

  /// Lightweight per-page interaction layer: a single hover [MouseRegion] and a
  /// single full-page [PdfOverlayInteractionRegion] for tap/long-press, both
  /// hit-testing the cached rects on demand. The *visuals* (highlight boxes and
  /// glosses) are painted in [_paintHighlights], so this builder — which pdfrx
  /// re-runs on every scroll frame — allocates only two widgets per page
  /// regardless of how many terms are highlighted.
  List<Widget> _buildPageOverlays(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
  ) {
    final occ = _occurrencesByPage[page.pageNumber];
    if (occ == null) {
      unawaited(_ensurePageComputed(page));
      return const [];
    }
    if (occ.isEmpty) return const [];

    return [
      Positioned.fill(
        child: MouseRegion(
          opaque: false,
          hitTestBehavior: HitTestBehavior.translucent,
          onHover: (e) {
            final entry = _hitEntry(e.localPosition, pageRect, page);
            if (entry != null) {
              _hideTimer?.cancel();
              _showPopup(entry, e.position);
            } else {
              _scheduleHide();
            }
          },
          onExit: (_) => _scheduleHide(),
          child: PdfOverlayInteractionRegion(
            onTap: (d) {
              final entry = _hitEntry(d.localPosition, pageRect, page);
              if (entry == null) return false; // let pdfrx handle the tap
              _showPopup(entry, d.globalPosition);
              return true;
            },
            onLongPress: (d) {
              final entry = _hitEntry(d.localPosition, pageRect, page);
              if (entry == null) return false;
              unawaited(_openEdit(entry));
              return true;
            },
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ];
  }

  /// The smallest highlighted term whose rect contains [local] (page-overlay
  /// coordinates), or null. Mapping happens only on a pointer event, not per
  /// frame, so this stays cheap even with many highlights on a page.
  DictionaryEntry? _hitEntry(Offset local, Rect pageRect, PdfPage page) {
    final occ = _occurrencesByPage[page.pageNumber];
    if (occ == null) return null;
    DictionaryEntry? best;
    var bestArea = double.infinity;
    for (final o in occ) {
      final entry = _dictState.byId[o.entryId];
      if (entry == null || !entry.highlightEnabled) continue;
      for (final pr in o.rects) {
        final r = _mapRect(pr, pageRect, page);
        if (r.contains(local)) {
          final area = r.width * r.height;
          if (area < bestArea) {
            bestArea = area;
            best = entry;
          }
        }
      }
    }
    return best;
  }

  /// Paints dictionary highlight boxes and inline glosses directly onto the
  /// page canvas (document coordinates). Runs inside pdfrx's page paint, so it
  /// is GPU-cheap and avoids rebuilding widgets while scrolling.
  void _paintHighlights(Canvas canvas, Rect pageRect, PdfPage page) {
    final occ = _occurrencesByPage[page.pageNumber];
    if (occ == null || occ.isEmpty) return;
    final s = _settings;
    final showGloss = s.inlineTranslationEnabled;

    // Invalidate the gloss text cache if the gloss style changed.
    final sig =
        '${s.inlineGlossColor}|${s.inlineGlossBgColor}|'
        '${s.inlineGlossFontScale}|${s.inlineGlossLetterSpacing}|'
        '${s.inlineGlossAlignment.id}';
    if (sig != _glossStyleSig) {
      _glossStyleSig = sig;
      _disposeGlossPainters();
    }

    final fill = Paint()..style = PaintingStyle.fill;
    for (final o in occ) {
      final entry = _dictState.byId[o.entryId];
      if (entry == null || !entry.highlightEnabled || o.rects.isEmpty) continue;
      final colorVal = entry.colorValue ?? s.highlightColor;
      if (!isNoColor(colorVal)) {
        fill.color = Color(colorVal);
        for (final pr in o.rects) {
          final r = pr.toRectInDocument(page: page, pageRect: pageRect);
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(2)),
            fill,
          );
        }
      }
      if (showGloss) {
        final translation = entry.translation?.trim();
        if (translation != null && translation.isNotEmpty) {
          final first = o.rects.first.toRectInDocument(
            page: page,
            pageRect: pageRect,
          );
          _paintGloss(canvas, first, translation, s, pageRect);
        }
      }
    }
  }

  void _paintGloss(
    Canvas canvas,
    Rect wordRect,
    String text,
    AppSettings s,
    Rect pageRect,
  ) {
    final fontSize = (wordRect.height * s.inlineGlossFontScale).clamp(
      4.0,
      200.0,
    );
    final key = '$text ${fontSize.toStringAsFixed(1)}';
    var tp = _glossPainters[key];
    if (tp == null) {
      tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Color(s.inlineGlossColor),
            fontSize: fontSize,
            height: 1.0,
            fontWeight: FontWeight.w500,
            letterSpacing: s.inlineGlossLetterSpacing,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
        // Lay out at a fixed generous width (document points) rather than the
        // page width, so the text+size cache key stays valid across pages of
        // different widths. Glosses are short, so this never actually wraps.
      )..layout(maxWidth: 3000.0);
      // Evict the single oldest entry when over cap — never dispose the whole
      // cache mid-paint (other painters may still be needed this frame).
      if (_glossPainters.length >= 256) {
        final oldest = _glossPainters.keys.first;
        _glossPainters.remove(oldest)?.dispose();
      }
      _glossPainters[key] = tp;
    }

    final top = wordRect.bottom + s.inlineGlossVerticalOffset * wordRect.height;
    final double anchored;
    switch (s.inlineGlossAlignment) {
      case GlossAlignment.left:
        anchored = wordRect.left;
      case GlossAlignment.center:
        anchored = wordRect.center.dx - tp.width / 2;
      case GlossAlignment.right:
        anchored = wordRect.right - tp.width;
    }
    // Keep the gloss within the page horizontally.
    final maxLeft = (pageRect.right - tp.width).clamp(
      pageRect.left,
      pageRect.right,
    );
    final left = anchored.clamp(pageRect.left, maxLeft);
    if (!isNoColor(s.inlineGlossBgColor)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left - 1, top, tp.width + 2, tp.height),
          const Radius.circular(2),
        ),
        Paint()..color = Color(s.inlineGlossBgColor),
      );
    }
    tp.paint(canvas, Offset(left, top));
  }

  void _showPopup(DictionaryEntry entry, Offset global) {
    _hideTimer?.cancel();
    if (_popup?.entry.id == entry.id) return; // already showing this term
    final box = _stackKey.currentContext?.findRenderObject();
    final local = box is RenderBox ? box.globalToLocal(global) : global;
    setState(() => _popup = _PopupModel(entry, local));
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted && _popup != null) setState(() => _popup = null);
    });
  }

  Future<void> _openEdit(DictionaryEntry entry) async {
    setState(() => _popup = null);
    await AddEntrySheet.show(
      context,
      documentId: widget.document.id,
      existing: entry,
    );
  }

  void _onSelectionChange(PdfTextSelection selection) {
    _selectionDebounce?.cancel();
    final gen = ++_selectionGeneration;
    if (!selection.hasSelectedText) {
      if (_selectedText != null) {
        setState(() {
          _selectedText = null;
          _selectedSourceWord = null;
        });
      }
      return;
    }
    // Short debounce (pdfrx already debounces ~300ms before calling us); fetch
    // the selection ranges ONCE and derive both the text and the parent word
    // from them, instead of calling getSelectedText + getSelectedTextRanges
    // separately (each loads structured text on the engine).
    _selectionDebounce = Timer(const Duration(milliseconds: 150), () async {
      final ranges = await selection.getSelectedTextRanges();
      // Bail if unmounted or a newer selection change superseded this one while
      // we were awaiting (cancel() can't stop an already-running async body).
      if (!mounted || gen != _selectionGeneration) return;
      // Collapse whitespace and drop leading/trailing punctuation (e.g. a
      // trailing comma/period from double-clicking "oblate,").
      final raw = ranges
          .map((r) => r.text)
          .join()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final text = TextNormalizer.trimEdgePunctuation(raw);
      final parent = text.isEmpty ? null : _detectParentWord(ranges, text);
      setState(() {
        _selectedText = text.isEmpty ? null : text;
        _selectedSourceWord = parent;
      });
    });
  }

  /// If [text] is a single word selected from *inside* a longer word, return
  /// that longer (parent) word; otherwise null. Used to default new entries to
  /// sub-word matching and to remember where they came from.
  String? _detectParentWord(List<PdfPageTextRange> ranges, String text) {
    if (text.contains(' ')) return null; // multi-word selection
    try {
      if (ranges.length != 1) return null;
      final r = ranges.first;
      final full = r.pageText.fullText;
      final selStart = r.start.clamp(0, full.length);
      final selEnd = r.end.clamp(0, full.length);
      if (selStart >= selEnd) return null;
      // Find the single word token that fully encloses the selection. Using the
      // tokenizer keeps offsets rune-aligned (no surrogate-half indexing) and
      // means a comma/space captured by the selection lands outside any token,
      // so it correctly reads as "not a sub-word selection".
      for (final tok in TextNormalizer.tokenize(full)) {
        if (tok.start > selStart) break; // tokens are ordered; gone past it
        if (tok.end < selEnd) continue;
        // tok.start <= selStart && tok.end >= selEnd: selection lies inside it.
        if (tok.start == selStart && tok.end == selEnd) {
          return null; // whole word selected, not a sub-part
        }
        final parent = tok.text;
        if (parent.isEmpty ||
            TextNormalizer.normalizeKey(parent) ==
                TextNormalizer.normalizeKey(text)) {
          return null;
        }
        return parent;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Find an entry for [text], preferring one scoped to this document and
  /// falling back to a global entry.
  DictionaryEntry? _findExisting(String text) {
    final notifier = ref.read(dictionaryControllerProvider.notifier);
    return notifier.findByTerm(text, scopeDocumentId: widget.document.id) ??
        notifier.findByTerm(text);
  }

  Future<void> _addSelected() async {
    final text = _selectedText;
    if (text == null) return;
    final existing = _findExisting(text);
    final saved = await AddEntrySheet.show(
      context,
      documentId: widget.document.id,
      initialTerm: text,
      initialSourceWord: existing == null ? _selectedSourceWord : null,
      existing: existing,
    );
    if (saved == true && mounted) {
      setState(() {
        _selectedText = null;
        _selectedSourceWord = null;
      });
    }
  }

  static bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows;

  bool _onGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    // Desktop: double-click selects the word under the cursor (pdfrx has no
    // built-in double-tap selection). The selection-change callback then
    // surfaces the "Add" bar.
    if (details.type == PdfViewerGeneralTapType.doubleTap) {
      if (_isDesktop && details.tapOn != PdfViewerPart.background) {
        final selection = controller.textSelectionDelegate;
        if (selection.isTextSelectionEnabled) {
          unawaited(selection.selectWord(details.documentPosition));
          return true; // handled
        }
      }
      return false;
    }
    if (details.type == PdfViewerGeneralTapType.tap && _popup != null) {
      setState(() => _popup = null);
    }
    return false; // never consume; let the viewer handle the tap normally
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    final count = document.pages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.isReady) return;
      ref
          .read(libraryControllerProvider.notifier)
          .updatePageCount(widget.document, count);
      _restoreView(controller, count);
      if (_searcher == null) {
        // Creating the searcher changes the paint-callback set, so the
        // memoized params rebuild once on the next build().
        final searcher = PdfTextSearcher(controller)
          ..addListener(_onSearchChanged);
        setState(() => _searcher = searcher);
      }
    });
  }

  /// Restore the exact saved view (scroll + zoom); fall back to the last page.
  void _restoreView(PdfViewerController controller, int pageCount) {
    final saved = widget.document.viewMatrix;
    final matrix = saved == null ? null : _parseMatrix(saved);
    if (matrix != null) {
      controller.value = matrix; // setter clamps to the safe range
      return;
    }
    final last = widget.document.lastPage;
    if (last > 1 && last <= pageCount) {
      controller.goToPage(pageNumber: last);
    }
  }

  /// Save the current view (page + serialized matrix), debounced.
  void _onViewChanged() {
    if (!_controller.isReady) return;
    _viewSaveDebounce?.cancel();
    _viewSaveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || !_controller.isReady) return;
      ref
          .read(libraryControllerProvider.notifier)
          .saveView(
            widget.document.id,
            page: _controller.pageNumber ?? widget.document.lastPage,
            viewMatrix: _controller.value.storage.join(','),
          );
    });
  }

  static Matrix4? _parseMatrix(String s) {
    try {
      final parts = s.split(',').map(double.parse).toList(growable: false);
      if (parts.length != 16) return null;
      return Matrix4.fromList(parts);
    } catch (_) {
      return null;
    }
  }

  /// First page to render, so we open near the saved position instead of
  /// painting page 1 and then jumping in [_restoreView].
  int? _calculateInitialPageNumber(
    PdfDocument document,
    PdfViewerController controller,
  ) {
    final last = widget.document.lastPage;
    return (last > 1 && last <= document.pages.length) ? last : null;
  }

  /// (Re)build the memoized [PdfViewerParams] only when an input it depends on
  /// changes — highlighting on/off, or whether the searcher exists. Keeping the
  /// same params object across builds stops pdfrx from treating params as
  /// "changed" on every setState (which it does by comparing closures).
  void _ensureViewerParams() {
    final highlighting = _settings.highlightingEnabled;
    final hasSearcher = _searcher != null;
    if (_viewerParams != null &&
        _paramsHighlighting == highlighting &&
        _paramsHasSearcher == hasSearcher) {
      return;
    }
    _paramsHighlighting = highlighting;
    _paramsHasSearcher = hasSearcher;
    _textSelectionParams ??= PdfTextSelectionParams(
      enabled: true,
      onTextSelectionChange: _onSelectionChange,
    );
    final paintCallbacks = <PdfViewerPagePaintCallback>[
      if (highlighting) _paintHighlights,
      if (_searcher != null) _searcher!.pageTextMatchPaintCallback,
    ];
    _viewerParams = PdfViewerParams(
      textSelectionParams: _textSelectionParams,
      viewerOverlayBuilder: _buildViewerOverlay,
      pageOverlaysBuilder: highlighting ? _buildPageOverlays : null,
      pagePaintCallbacks: paintCallbacks.isEmpty ? null : paintCallbacks,
      onGeneralTap: _onGeneralTap,
      onViewerReady: _onViewerReady,
      calculateInitialPageNumber: _calculateInitialPageNumber,
    );
  }

  /// Stable [PdfViewerParams.viewerOverlayBuilder] (the scroll thumb). Extracted
  /// to a method so it isn't a fresh closure on every build.
  List<Widget> _buildViewerOverlay(
    BuildContext context,
    Size size,
    PdfViewerHandleLinkTap handleLinkTap,
  ) {
    return [
      PdfViewerScrollThumb(
        controller: _controller,
        orientation: ScrollbarOrientation.right,
        thumbSize: const Size(40, 48),
        thumbBuilder: (context, thumbSize, pageNumber, controller) {
          final scheme = Theme.of(context).colorScheme;
          return Material(
            color: scheme.primary,
            elevation: 2,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(8),
            ),
            child: Center(
              child: Text(
                '${pageNumber ?? ''}',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _settings = ref.watch(settingsControllerProvider);
    _dictState = ref.watch(dictionaryControllerProvider);

    if (_dictState.revision != _lastDictRevision ||
        _settings.learningLang != _learningLang) {
      _lastDictRevision = _dictState.revision;
      _learningLang = _settings.learningLang;
      _rebuildMatcher();
      _popup = null;
    }
    _ensureViewerParams();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Find in document (Ctrl+F)',
            icon: const Icon(Icons.search),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: _settings.highlightingEnabled
                ? 'Hide highlights'
                : 'Show highlights',
            icon: Icon(
              _settings.highlightingEnabled
                  ? Icons.highlight
                  : Icons.highlight_off,
            ),
            onPressed: () => ref
                .read(settingsControllerProvider.notifier)
                .mutate(
                  (s) =>
                      s.copyWith(highlightingEnabled: !s.highlightingEnabled),
                ),
          ),
        ],
        bottom: _searchVisible
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: _buildSearchBar(context),
              )
            : null,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            key: _stackKey,
            children: [
              PdfViewer.file(
                widget.document.filePath,
                controller: _controller,
                params: _viewerParams!,
              ),
              if (_popup != null) _buildPopup(constraints),
              if (_selectedText != null) _buildSelectionBar(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final searcher = _searcher;
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final count = searcher?.matches.length ?? 0;
    final idx = searcher?.currentIndex;
    final String status;
    if (!hasQuery) {
      status = '';
    } else if (count == 0) {
      status = (searcher?.isSearching ?? false) ? '…' : 'No results';
    } else {
      status = '${(idx ?? 0) + 1}/$count';
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Find in document',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (q) =>
                    searcher?.startTextSearch(q, caseInsensitive: true),
                onSubmitted: (_) => searcher?.goToNextMatch(),
              ),
            ),
            Text(status, style: theme.textTheme.bodySmall),
            IconButton(
              tooltip: 'Previous',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: count == 0 ? null : () => searcher?.goToPrevMatch(),
            ),
            IconButton(
              tooltip: 'Next',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: count == 0 ? null : () => searcher?.goToNextMatch(),
            ),
            IconButton(
              tooltip: 'Close (Esc)',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close),
              onPressed: _closeSearch,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopup(BoxConstraints constraints) {
    final popup = _popup!;
    const width = 340.0;
    final anchor = popup.anchorLocal;
    var left = anchor.dx - width / 2;
    left = left.clamp(
      8.0,
      (constraints.maxWidth - width - 8).clamp(8.0, double.infinity),
    );
    // Prefer placing below the anchor; flip above if it would run off-screen.
    var top = anchor.dy + 18;
    if (top + 200 > constraints.maxHeight) {
      top = (anchor.dy - 220).clamp(8.0, constraints.maxHeight - 8);
    }
    return Positioned(
      left: left,
      top: top,
      child: TranslationPopupCard(
        entry: popup.entry,
        maxWidth: width,
        onEdit: () => _openEdit(popup.entry),
        onPointerEnter: () => _hideTimer?.cancel(),
        onPointerExit: _scheduleHide,
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final theme = Theme.of(context);
    final existing = _findExisting(_selectedText!);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '“${_selectedText!}”',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _addSelected,
                    icon: Icon(
                      existing == null ? Icons.add : Icons.edit_outlined,
                    ),
                    label: Text(existing == null ? 'Add' : 'Edit'),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () => setState(() => _selectedText = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A matched term occurrence on a page, as PDF-space rects (one per text line).
class _Occurrence {
  const _Occurrence(this.entryId, this.rects);
  final int entryId;
  final List<PdfRect> rects;
}

class _PopupModel {
  const _PopupModel(this.entry, this.anchorLocal);
  final DictionaryEntry entry;
  final Offset anchorLocal;
}
