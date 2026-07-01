import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// SelectedContent lives in the rendering library (used by SelectionArea's
// onSelectionChanged) and is not re-exported through material/widgets.
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../models/dictionary_entry.dart';
import '../../models/library_document.dart';
import '../../services/book/book_content.dart';
import '../../services/book/book_loader.dart';
import '../../state/dictionary_controller.dart';
import '../../state/library_controller.dart';
import '../../state/settings_controller.dart';
import '../../text/term_matcher.dart';
import '../../text/text_normalizer.dart';
import 'add_entry_sheet.dart';
import 'translation_popup.dart';

/// Reads a reflowable, text-based document (EPUB, MOBI, FB2, TXT, HTML,
/// Markdown, RTF). The book is parsed into flowing [BookBlock]s; dictionary
/// terms are highlighted inline with the same hover/tap translation popup,
/// inline glosses, text-selection "add", find, and reading-position memory as
/// the PDF reader.
class TextReaderScreen extends ConsumerStatefulWidget {
  const TextReaderScreen({
    super.key,
    required this.document,
    this.initialBlockIndex,
  });

  final LibraryDocument document;

  /// If set, open scrolled to this paragraph block instead of the saved scroll
  /// position — used when jumping to a usage from the Dictionary.
  final int? initialBlockIndex;

  @override
  ConsumerState<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends ConsumerState<TextReaderScreen> {
  final _scrollController = ScrollController();
  final _stackKey = GlobalKey();

  BookContent? _book;
  Object? _loadError;
  bool _loading = true;

  // Cumulative character offset at the start of each block, for estimating a
  // scroll position when jumping (find / restore) in a lazily-built list.
  List<int> _cumChars = const [];
  int _totalChars = 1;

  TermMatcher? _matcher;
  int _lastDictRevision = -1;
  String _learningLang = '';

  _Popup? _popup;
  Timer? _hideTimer;
  Timer? _saveDebounce;

  String? _selectedText;

  // Find-in-document.
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchVisible = false;
  List<int> _searchHits = const []; // block indices, one per occurrence
  int _searchIndex = 0;

  late AppSettings _settings;
  late DictionaryState _dictState;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _load();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    _hideTimer?.cancel();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final book = await loadBook(
        widget.document.filePath,
        widget.document.format,
      );
      if (!mounted) return;
      _book = book;
      _computeCumulative(book);
      setState(() => _loading = false);
      // Estimate a page count (~1800 chars/page) for the library listing.
      final pages = (book.totalChars / 1800).ceil().clamp(1, 1000000);
      ref
          .read(libraryControllerProvider.notifier)
          .updatePageCount(widget.document, pages);
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreScroll());
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e;
        });
      }
    }
  }

  void _computeCumulative(BookContent book) {
    final cum = List<int>.filled(book.blocks.length, 0);
    var sum = 0;
    for (var i = 0; i < book.blocks.length; i++) {
      cum[i] = sum;
      sum += book.blocks[i].text.length + 1;
    }
    _cumChars = cum;
    _totalChars = sum == 0 ? 1 : sum;
  }

  void _restoreScroll() {
    final jump = widget.initialBlockIndex;
    if (jump != null && jump >= 0 && jump < _cumChars.length) {
      _jumpToBlock(jump, animate: false);
      return;
    }
    final saved = widget.document.viewMatrix;
    final offset = saved == null ? null : double.tryParse(saved);
    if (offset != null && _scrollController.hasClients) {
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, max));
    }
  }

  void _onScroll() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || !_scrollController.hasClients) return;
      // Reflowable docs store the scroll pixel offset in `viewMatrix` (the PDF
      // reader stores a 16-float matrix there; a book always opens here so the
      // two interpretations never collide).
      ref
          .read(libraryControllerProvider.notifier)
          .saveView(
            widget.document.id,
            page: 1,
            viewMatrix: _scrollController.offset.toStringAsFixed(1),
          );
    });
  }

  // --- Keyboard (Find / Escape) ---------------------------------------------

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final kb = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        (kb.isControlPressed || kb.isMetaPressed)) {
      _openSearch();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _searchVisible) {
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
    setState(() {
      _searchVisible = false;
      _searchHits = const [];
      _searchIndex = 0;
      _searchController.clear();
    });
  }

  void _toggleSearch() => _searchVisible ? _closeSearch() : _openSearch();

  // --- Matching --------------------------------------------------------------

  void _rebuildMatcher() {
    final terms = ref
        .read(dictionaryControllerProvider.notifier)
        .matchableTermsFor(widget.document.id, _learningLang);
    _matcher = TermMatcher(terms);
  }

  // --- Popup -----------------------------------------------------------------

  void _showPopup(DictionaryEntry entry, Offset global, String passage) {
    _hideTimer?.cancel();
    if (_popup?.entry.id == entry.id) return;
    final box = _stackKey.currentContext?.findRenderObject();
    final local = box is RenderBox ? box.globalToLocal(global) : global;
    setState(() => _popup = _Popup(entry, local, passage));
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted && _popup != null) setState(() => _popup = null);
    });
  }

  Future<void> _openEdit(DictionaryEntry entry, {String? passage}) async {
    setState(() => _popup = null);
    await AddEntrySheet.show(
      context,
      documentId: widget.document.id,
      contextPassage: passage,
      existing: entry,
    );
  }

  // --- Selection -> add ------------------------------------------------------

  void _onSelectionChanged(SelectedContent? content) {
    final raw = content?.plainText ?? '';
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final text = TextNormalizer.trimEdgePunctuation(collapsed);
    // Ignore very long selections (whole paragraphs) for the "add" affordance.
    final value = (text.isEmpty || text.length > 120) ? null : text;
    if (value != _selectedText) setState(() => _selectedText = value);
  }

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
      contextPassage: _passageForSelection(text),
      existing: existing,
    );
    if (saved == true && mounted) setState(() => _selectedText = null);
  }

  /// The paragraph (book block) the current selection sits in, for the
  /// add-entry sheet's DeepL "in context" translation. Prefers blocks currently
  /// on screen so a word that recurs resolves to the one being read.
  String? _passageForSelection(String text) {
    final book = _book;
    final needle = text.trim().toLowerCase();
    if (book == null || needle.isEmpty) return null;
    bool matches(int i) => book.blocks[i].text.toLowerCase().contains(needle);
    final (lo, hi) = _visibleBlockRange();
    for (var i = lo; i < hi; i++) {
      if (matches(i)) return book.blocks[i].text;
    }
    // Fall back to a whole-document scan if it wasn't in the estimated viewport.
    for (var i = 0; i < book.blocks.length; i++) {
      if (matches(i)) return book.blocks[i].text;
    }
    return null;
  }

  /// Estimated `[start, end)` range of block indices currently on screen, using
  /// the same linear char-offset↔scroll mapping as jump/restore, widened by a
  /// block on each side to tolerate the estimate.
  (int, int) _visibleBlockRange() {
    final book = _book;
    if (book == null) return (0, 0);
    final n = book.blocks.length;
    if (!_scrollController.hasClients) return (0, n);
    final pos = _scrollController.position;
    final max = pos.maxScrollExtent;
    if (max <= 0) return (0, n);
    final topFrac = (_scrollController.offset / max).clamp(0.0, 1.0);
    final botFrac = ((_scrollController.offset + pos.viewportDimension) / max)
        .clamp(0.0, 1.0);
    final lo = (_blockAtChar(topFrac * _totalChars) - 1).clamp(0, n);
    final hi = (_blockAtChar(botFrac * _totalChars) + 2).clamp(0, n);
    return (lo, hi);
  }

  /// Index of the last block whose cumulative start char is `<= charOffset`.
  int _blockAtChar(double charOffset) {
    final cum = _cumChars;
    if (cum.isEmpty) return 0;
    var lo = 0, hi = cum.length - 1, ans = 0;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= charOffset) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  // --- Find navigation -------------------------------------------------------

  void _runSearch(String query) {
    final q = query.trim().toLowerCase();
    final book = _book;
    if (q.isEmpty || book == null) {
      setState(() {
        _searchHits = const [];
        _searchIndex = 0;
      });
      return;
    }
    final hits = <int>[];
    for (var i = 0; i < book.blocks.length; i++) {
      final lower = book.blocks[i].text.toLowerCase();
      var idx = lower.indexOf(q);
      while (idx >= 0) {
        hits.add(i);
        idx = lower.indexOf(q, idx + q.length);
      }
    }
    setState(() {
      _searchHits = hits;
      _searchIndex = 0;
    });
    if (hits.isNotEmpty) _jumpToBlock(hits.first);
  }

  void _moveSearch(int delta) {
    if (_searchHits.isEmpty) return;
    final n = _searchHits.length;
    setState(() => _searchIndex = ((_searchIndex + delta) % n + n) % n);
    _jumpToBlock(_searchHits[_searchIndex]);
  }

  void _jumpToBlock(int blockIndex, {bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final frac = _cumChars[blockIndex] / _totalChars;
    final max = _scrollController.position.maxScrollExtent;
    final target = (frac * max).clamp(0.0, max);
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  // --- Build -----------------------------------------------------------------

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
            tooltip: 'Find in document (Ctrl+F)',
            icon: const Icon(Icons.search),
            onPressed: _book == null ? null : _toggleSearch,
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
              Positioned.fill(child: _buildBody(context)),
              if (_popup != null) _buildPopup(constraints),
              if (_selectedText != null) _buildSelectionBar(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null || _book == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not open this document.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                '$_loadError',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final book = _book!;
    final matcher = _settings.highlightingEnabled ? _matcher : null;
    // Constrain the reading column width for comfortable line length on wide
    // (desktop) windows.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SelectionArea(
          onSelectionChanged: _onSelectionChanged,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            itemCount: book.blocks.length,
            itemBuilder: (context, i) => _BlockView(
              key: ValueKey('blk$i'),
              block: book.blocks[i],
              matcher: matcher,
              dictState: _dictState,
              settings: _settings,
              onHoverEntry: _showPopup,
              onHoverExit: _scheduleHide,
              onTapEntry: _showPopup,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final count = _searchHits.length;
    final status = !hasQuery
        ? ''
        : (count == 0 ? 'No results' : '${_searchIndex + 1}/$count');
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
                onChanged: _runSearch,
                onSubmitted: (_) => _moveSearch(1),
              ),
            ),
            Text(status, style: theme.textTheme.bodySmall),
            IconButton(
              tooltip: 'Previous',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: count == 0 ? null : () => _moveSearch(-1),
            ),
            IconButton(
              tooltip: 'Next',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: count == 0 ? null : () => _moveSearch(1),
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
        onEdit: () => _openEdit(popup.entry, passage: popup.passage),
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

class _Popup {
  const _Popup(this.entry, this.anchorLocal, this.passage);
  final DictionaryEntry entry;
  final Offset anchorLocal;

  /// The paragraph this term was hovered/tapped in, for the add-entry sheet's
  /// in-context translation when the term is edited from its highlight.
  final String passage;
}

typedef _EntryAt =
    void Function(DictionaryEntry entry, Offset global, String passage);

/// One paragraph/heading. A [StatefulWidget] so the tap [GestureRecognizer]s it
/// creates for highlighted spans are disposed when the row scrolls out of view
/// or rebuilds (avoiding recognizer leaks in the lazy list).
class _BlockView extends StatefulWidget {
  const _BlockView({
    super.key,
    required this.block,
    required this.matcher,
    required this.dictState,
    required this.settings,
    required this.onHoverEntry,
    required this.onHoverExit,
    required this.onTapEntry,
  });

  final BookBlock block;
  final TermMatcher? matcher;
  final DictionaryState dictState;
  final AppSettings settings;
  final _EntryAt onHoverEntry;
  final VoidCallback onHoverExit;
  final _EntryAt onTapEntry;

  @override
  State<_BlockView> createState() => _BlockViewState();
}

class _BlockViewState extends State<_BlockView> {
  final List<TapGestureRecognizer> _recognizers = [];
  // Recognizers from the previous build pass, disposed AFTER the frame: the old
  // span may still be referenced by the live render object this frame, so
  // disposing mid-build could free a recognizer that a pointer event then hits.
  final List<TapGestureRecognizer> _retired = [];
  bool _flushScheduled = false;

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    for (final r in _retired) {
      r.dispose();
    }
    _recognizers.clear();
    _retired.clear();
    super.dispose();
  }

  void _retireRecognizers() {
    _retired.addAll(_recognizers);
    _recognizers.clear();
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      for (final r in _retired) {
        r.dispose();
      }
      _retired.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Retire recognizers from the previous build; new ones are created below.
    _retireRecognizers();

    final theme = Theme.of(context);
    final base = widget.block.heading
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge?.copyWith(height: 1.55, fontSize: 17);

    final padding = widget.block.heading
        ? const EdgeInsets.only(top: 22, bottom: 8)
        : const EdgeInsets.only(bottom: 14);

    final matcher = widget.matcher;
    if (matcher == null || matcher.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(widget.block.text, style: base),
      );
    }

    final span = _buildSpan(base);
    return Padding(
      padding: padding,
      child: Text.rich(span, style: base),
    );
  }

  TextSpan _buildSpan(TextStyle? base) {
    final text = widget.block.text;
    final matches = widget.matcher!.findMatches(text);
    // Resolve overlaps: keep earliest-start, then longest, non-overlapping.
    matches.sort((a, b) {
      final s = a.start.compareTo(b.start);
      return s != 0 ? s : b.length.compareTo(a.length);
    });
    final chosen = <TermMatch>[];
    var lastEnd = 0;
    for (final m in matches) {
      if (m.start >= lastEnd) {
        chosen.add(m);
        lastEnd = m.end;
      }
    }

    final settings = widget.settings;
    final showGloss = settings.inlineTranslationEnabled;
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final m in chosen) {
      final entry = widget.dictState.byId[m.entryId];
      if (entry == null || !entry.highlightEnabled) continue;
      if (m.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      final colorVal = entry.colorValue ?? settings.highlightColor;
      final recognizer = TapGestureRecognizer()
        ..onTapUp = (d) => widget.onTapEntry(entry, d.globalPosition, text);
      _recognizers.add(recognizer);

      children.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: isNoColor(colorVal) ? null : Color(colorVal),
          ),
          recognizer: recognizer,
          mouseCursor: SystemMouseCursors.click,
          onEnter: (e) => widget.onHoverEntry(entry, e.position, text),
          onExit: (_) => widget.onHoverExit(),
        ),
      );

      // Mark terms with more than one translation variant with a small dot at
      // the word's top-right (the popup lists every variant on hover).
      if (entry.hasMultipleTranslations) {
        children.add(
          const WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Padding(
              padding: EdgeInsets.only(left: 1.5),
              child: SizedBox(
                width: 5,
                height: 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(kVariantMarkerColor),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final translation = showGloss ? entry.glossText?.trim() : null;
      if (translation != null && translation.isNotEmpty) {
        children.add(
          TextSpan(
            text: ' [$translation]',
            style: TextStyle(
              color: Color(settings.inlineGlossColor),
              fontSize: (base?.fontSize ?? 16) * 0.72,
              letterSpacing: settings.inlineGlossLetterSpacing,
              backgroundColor: isNoColor(settings.inlineGlossBgColor)
                  ? null
                  : Color(settings.inlineGlossBgColor),
            ),
          ),
        );
      }
      cursor = m.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(children: children);
  }
}
