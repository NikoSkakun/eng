/// Extracts the passage (ideally a paragraph) surrounding a selection, used to
/// show a word/phrase "in context" and to translate that context.
///
/// The PDF reader only has the page's flat `fullText` plus the selection's
/// code-unit offsets, so the surrounding paragraph has to be recovered from the
/// text itself. The text reader, by contrast, already holds real paragraphs
/// (`BookBlock`s) and uses those directly.
library;

// A blank line — the strongest paragraph separator. Rare in text extracted
// from PDFs (where most line breaks are just wraps) but honoured when present
// so a real paragraph is never overrun into its neighbours.
final RegExp _paragraphBreak = RegExp(r'\n[ \t]*\n');

// A sentence terminator with an optional closing quote/bracket. Used to trim
// the window's far edges back to whole sentences when no paragraph break caps
// it (the common PDF case), so the passage reads cleanly.
final RegExp _sentenceEnd = RegExp('[.!?]["”\'’)\\]]?');

// The same, followed by the whitespace that starts the next sentence — used to
// find where the sentence *after* a boundary begins.
final RegExp _sentenceEndThenSpace = RegExp('[.!?]["”\'’)\\]]?\\s+');

final RegExp _whitespace = RegExp(r'\s');

/// Return the passage of [text] surrounding the half-open selection
/// `[start, end)`.
///
/// The result is bounded by, in order of preference: the enclosing paragraph
/// (blank lines on either side), then — when no blank line is near — whole
/// sentence boundaries, and finally a hard [maxChars]-per-side window snapped
/// to word boundaries so it never begins or ends mid-word. The selection itself
/// is always included.
///
/// Offsets are code-unit indices (as produced by pdfrx's page text). Newlines
/// are preserved in the output; callers that want flowing text should pass the
/// result through `TextNormalizer.joinWrappedLines`.
String extractContextPassage(
  String text,
  int start,
  int end, {
  int maxChars = 400,
}) {
  if (text.isEmpty) return '';
  final n = text.length;
  start = start.clamp(0, n);
  end = end.clamp(start, n);

  final left = _leftBound(text, start, maxChars);
  final right = _rightBound(text, end, maxChars, n);
  if (right <= left) return '';
  return text.substring(left, right).trim();
}

int _leftBound(String text, int start, int maxChars) {
  // Never cross the paragraph break immediately before the selection.
  final paraLeft = _lastEnd(_paragraphBreak, text.substring(0, start));
  final floor = paraLeft ?? 0;
  var lo = start - maxChars;
  if (lo < floor) lo = floor;
  if (lo <= floor) return lo; // sitting on a clean paragraph start (or doc top)

  // Capped mid-paragraph: begin at a clean sentence (or at worst word) start so
  // the passage doesn't open mid-sentence.
  final window = text.substring(lo, start);
  final sentence = _lastEnd(_sentenceEndThenSpace, window);
  if (sentence != null) return lo + sentence;
  final firstSpace = window.indexOf(_whitespace);
  return firstSpace >= 0 ? lo + firstSpace + 1 : lo;
}

int _rightBound(String text, int end, int maxChars, int n) {
  // Never cross the paragraph break immediately after the selection.
  final after = text.substring(end);
  final paraAfter = _paragraphBreak.firstMatch(after);
  final ceil = paraAfter == null ? n : end + paraAfter.start;
  var hi = end + maxChars;
  if (hi > ceil) hi = ceil;
  if (hi >= ceil) return hi; // sitting on a clean paragraph end (or doc end)

  // Capped mid-paragraph: end at the last whole sentence (or at worst word) in
  // the window so the passage doesn't trail off mid-sentence.
  final window = text.substring(end, hi);
  final sentence = _lastEnd(_sentenceEnd, window);
  if (sentence != null) return end + sentence;
  final lastSpace = window.lastIndexOf(_whitespace);
  return lastSpace >= 0 ? end + lastSpace : hi;
}

/// End offset of the last match of [pattern] in [s], or null if none.
int? _lastEnd(RegExp pattern, String s) {
  int? last;
  for (final m in pattern.allMatches(s)) {
    last = m.end;
  }
  return last;
}
