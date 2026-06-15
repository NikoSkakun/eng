import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/settings_store.dart';
import '../../models/dictionary_entry.dart';
import '../../models/library_document.dart';
import '../../state/dictionary_controller.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';
import '../../text/term_matcher.dart';
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
  Timer? _selectionDebounce;
  Timer? _positionDebounce;

  // Captured at build time so the pdfrx callbacks (which can fire between our
  // builds, e.g. on scroll) always see the latest values.
  late AppSettings _settings;
  late DictionaryState _dictState;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _selectionDebounce?.cancel();
    _positionDebounce?.cancel();
    super.dispose();
  }

  void _rebuildMatcher() {
    final terms = ref
        .read(dictionaryControllerProvider.notifier)
        .matchableTermsFor(widget.document.id, _learningLang);
    _matcher = TermMatcher(terms);
    _matcherGeneration++;
    _occurrencesByPage.clear();
    _loadingPages.clear();
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
    try {
      final pageText = await page.loadStructuredText();
      // dictionary/language changed mid-flight
      if (!mounted || gen != _matcherGeneration) {
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
      if (gen != _matcherGeneration) return;
      _occurrencesByPage[n] = occ;
    } catch (_) {
      if (gen != _matcherGeneration) return;
      _occurrencesByPage[n] = const <_Occurrence>[];
    } finally {
      // Only the current-generation compute owns the page's loading slot and
      // its repaint; a stale compute leaves the fresh one's state untouched.
      if (gen == _matcherGeneration) {
        _loadingPages.remove(n);
        if (mounted) setState(() {});
      }
    }
  }

  /// Map a PDF-space rect (bottom-left origin) to the page overlay's
  /// Flutter-space rect. pdfrx's [PdfRectExt.toRect] handles the Y-flip,
  /// page rotation and uniform scaling correctly; the overlay Stack is sized
  /// to [pageRect], so the page-local result lines up with the highlights.
  Rect _mapRect(PdfRect pr, Rect pageRect, PdfPage page) =>
      pr.toRect(page: page, scaledPageSize: pageRect.size);

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

    final defaultColor = Color(_settings.highlightColor);
    final hits = <_HitRect>[];
    final widgets = <Widget>[];

    for (final o in occ) {
      final entry = _dictState.byId[o.entryId];
      if (entry == null || !entry.highlightEnabled) continue;
      final color = entry.colorValue != null
          ? Color(entry.colorValue!)
          : defaultColor;
      for (final pr in o.rects) {
        final r = _mapRect(pr, pageRect, page);
        if (r.width <= 0 || r.height <= 0) continue;
        hits.add(_HitRect(r, entry));
        widgets.add(
          Positioned.fromRect(
            rect: r,
            child: PdfOverlayInteractionRegion(
              onTap: (d) {
                _showPopup(entry, d.globalPosition);
                return true;
              },
              onLongPress: (d) {
                unawaited(_openEdit(entry));
                return true;
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      }
    }

    // A single transparent hover layer for the whole page. It tracks the mouse
    // (desktop) without blocking taps, panning or text selection; on touch
    // devices it never fires and the tap path above is used instead.
    widgets.insert(
      0,
      Positioned.fill(
        child: MouseRegion(
          opaque: false,
          hitTestBehavior: HitTestBehavior.translucent,
          onHover: (e) => _onHover(e.localPosition, e.position, hits),
          onExit: (_) => _scheduleHide(),
        ),
      ),
    );
    return widgets;
  }

  void _onHover(Offset pageLocal, Offset global, List<_HitRect> hits) {
    _HitRect? best;
    for (final h in hits) {
      if (h.rect.contains(pageLocal)) {
        if (best == null || h.rect.longestSide < best.rect.longestSide) {
          best = h;
        }
      }
    }
    if (best != null) {
      _hideTimer?.cancel();
      _showPopup(best.entry, global);
    } else {
      _scheduleHide();
    }
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
    if (!selection.hasSelectedText) {
      if (_selectedText != null) setState(() => _selectedText = null);
      return;
    }
    _selectionDebounce = Timer(const Duration(milliseconds: 300), () async {
      final raw = (await selection.getSelectedText()).trim();
      if (!mounted) return;
      final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      setState(() => _selectedText = text.isEmpty ? null : text);
    });
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
      existing: existing,
    );
    if (saved == true && mounted) setState(() => _selectedText = null);
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
      if (!mounted) return;
      ref
          .read(libraryControllerProvider.notifier)
          .updatePageCount(widget.document, count);
      final last = widget.document.lastPage;
      if (last > 1 && last <= count) {
        controller.goToPage(pageNumber: last);
      }
    });
  }

  void _onPageChanged(int? pageNumber) {
    if (pageNumber == null) return;
    _positionDebounce?.cancel();
    _positionDebounce = Timer(const Duration(milliseconds: 700), () {
      ref
          .read(libraryControllerProvider.notifier)
          .recordOpened(widget.document, page: pageNumber);
    });
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
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
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            key: _stackKey,
            children: [
              PdfViewer.file(
                widget.document.filePath,
                controller: _controller,
                params: PdfViewerParams(
                  textSelectionParams: PdfTextSelectionParams(
                    enabled: true,
                    onTextSelectionChange: _onSelectionChange,
                  ),
                  viewerOverlayBuilder: (context, size, handleLinkTap) => [
                    PdfViewerScrollThumb(
                      controller: _controller,
                      orientation: ScrollbarOrientation.right,
                      thumbSize: const Size(40, 48),
                      thumbBuilder:
                          (context, thumbSize, pageNumber, controller) {
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
                  ],
                  pageOverlaysBuilder: _settings.highlightingEnabled
                      ? _buildPageOverlays
                      : null,
                  onGeneralTap: _onGeneralTap,
                  onViewerReady: _onViewerReady,
                  onPageChanged: _onPageChanged,
                ),
              ),
              if (_popup != null) _buildPopup(constraints),
              if (_selectedText != null) _buildSelectionBar(context),
            ],
          );
        },
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

/// A hover/tap target rect (Flutter space) bound to its dictionary entry.
class _HitRect {
  const _HitRect(this.rect, this.entry);
  final Rect rect;
  final DictionaryEntry entry;
}

class _PopupModel {
  const _PopupModel(this.entry, this.anchorLocal);
  final DictionaryEntry entry;
  final Offset anchorLocal;
}
