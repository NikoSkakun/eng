import 'package:pdfrx/pdfrx.dart';

import '../../models/library_document.dart';
import '../../text/term_matcher.dart';
import '../../text/text_normalizer.dart';
import '../book/book_loader.dart';

/// One occurrence of a term shown in context — a paragraph (reflowable books)
/// or a windowed snippet around the match (PDF pages) — with where it came
/// from and the match range(s) inside [text].
class WordContext {
  WordContext({
    required this.documentId,
    required this.sourceTitle,
    required this.text,
    required this.highlights,
    this.page,
    this.blockIndex,
  });

  final int documentId;
  final String sourceTitle;

  /// The passage / snippet to display.
  final String text;

  /// Ranges within [text] (code-unit `[start, end)`) to emphasize.
  final List<({int start, int end})> highlights;

  /// Jump target for PDFs (1-based page), null for reflowable books.
  final int? page;

  /// Jump target for reflowable books (paragraph block index), null for PDFs.
  final int? blockIndex;
}

/// A unit of extracted text from a document.
class _Passage {
  _Passage(this.text, {required this.isParagraph, this.page, this.blockIndex});

  final String text;

  /// True for a clean reflowable paragraph (shown whole when short enough);
  /// false for a PDF page (we window around each match instead).
  final bool isParagraph;

  /// PDF page (1-based) or reflowable block index — the jump pointer.
  final int? page;
  final int? blockIndex;
}

/// Builds cross-library "concordance" contexts for a dictionary term: every
/// paragraph / snippet across the library where the term occurs.
///
/// Raw page/paragraph text is extracted once per document and cached for the
/// session, so changing the term or the selected sources only re-runs the cheap
/// in-memory [TermMatcher], not the expensive text extraction.
class WordContextsService {
  /// Paragraphs above this length are windowed around the match rather than
  /// shown whole, so a wall-of-text block (e.g. a TXT with no blank lines)
  /// doesn't drown the results.
  static const int _wholeParagraphMaxChars = 600;

  final Map<int, List<_Passage>> _passagesByDoc = {};

  /// Every context of [matcher] inside [doc]. Text extraction is cached per
  /// document; only the matching re-runs on subsequent calls.
  Future<List<WordContext>> contextsIn(
    LibraryDocument doc,
    TermMatcher matcher,
  ) async {
    if (matcher.isEmpty) return const [];
    final passages = await _passagesFor(doc);
    final out = <WordContext>[];
    for (final p in passages) {
      final matches = matcher.findMatches(p.text);
      if (matches.isEmpty) continue;

      if (p.isParagraph && p.text.length <= _wholeParagraphMaxChars) {
        // Show the whole paragraph with every occurrence highlighted.
        out.add(
          WordContext(
            documentId: doc.id,
            sourceTitle: doc.title,
            text: p.text,
            highlights: [for (final m in matches) (start: m.start, end: m.end)],
            page: p.page,
            blockIndex: p.blockIndex,
          ),
        );
      } else {
        // PDF page / oversized block: one focused snippet per occurrence.
        for (final m in matches) {
          final s = _window(p.text, m.start, m.end);
          out.add(
            WordContext(
              documentId: doc.id,
              sourceTitle: doc.title,
              text: s.text,
              highlights: [(start: s.start, end: s.end)],
              page: p.page,
              blockIndex: p.blockIndex,
            ),
          );
        }
      }
    }
    return out;
  }

  /// Drop cached text for a document (e.g. after it is edited or removed).
  void invalidate(int documentId) => _passagesByDoc.remove(documentId);

  Future<List<_Passage>> _passagesFor(LibraryDocument doc) async {
    final cached = _passagesByDoc[doc.id];
    if (cached != null) return cached;

    List<_Passage> result;
    try {
      if (doc.format.isPdf) {
        result = await _extractPdf(doc.filePath);
      } else if (doc.format.isReflowable) {
        final content = await loadBook(doc.filePath, doc.format);
        result = [
          for (var i = 0; i < content.blocks.length; i++)
            _Passage(content.blocks[i].text, isParagraph: true, blockIndex: i),
        ];
      } else {
        result = const [];
      }
    } catch (_) {
      // Unreadable/missing file or a parse failure — treat as no contexts.
      result = const [];
    }
    _passagesByDoc[doc.id] = result;
    return result;
  }

  Future<List<_Passage>> _extractPdf(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final out = <_Passage>[];
      for (final page in doc.pages) {
        try {
          // Wait until the page is really loaded (its text reads empty before
          // that) and isolate failures per page, so a single unreadable page
          // never discards the whole document's text.
          final src =
              await page.waitForLoaded(timeout: const Duration(seconds: 30)) ??
              page;
          final pageText = await src.loadStructuredText();
          // Join wrapped lines so each page reads as continuous prose; we then
          // window around each match rather than showing a whole page.
          final text = TextNormalizer.joinWrappedLines(pageText.fullText).trim();
          if (text.isEmpty) continue;
          out.add(_Passage(text, isParagraph: false, page: src.pageNumber));
        } catch (_) {
          continue; // skip this page, keep the rest of the document
        }
      }
      return out;
    } finally {
      await doc.dispose();
    }
  }

  /// Extract a readable window of text around `[start, end)`, snapping to word
  /// boundaries and adding ellipses when truncated. Returns the snippet plus the
  /// match range translated into snippet coordinates.
  static ({String text, int start, int end}) _window(
    String text,
    int start,
    int end, {
    int radius = 160,
  }) {
    var from = start - radius;
    if (from < 0) from = 0;
    var to = end + radius;
    if (to > text.length) to = text.length;
    // Don't cut mid-word.
    while (from > 0 &&
        _isWordChar(text.codeUnitAt(from - 1)) &&
        _isWordChar(text.codeUnitAt(from))) {
      from--;
    }
    while (to < text.length &&
        _isWordChar(text.codeUnitAt(to - 1)) &&
        _isWordChar(text.codeUnitAt(to))) {
      to++;
    }
    final prefix = from > 0 ? '… ' : '';
    final suffix = to < text.length ? ' …' : '';
    return (
      text: '$prefix${text.substring(from, to)}$suffix',
      start: prefix.length + (start - from),
      end: prefix.length + (end - from),
    );
  }

  static bool _isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c > 0x7F; // letters with diacritics, Cyrillic, etc.
}
