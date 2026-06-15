/// Text normalization shared by the matching engine and dictionary storage.
///
/// Two distinct needs are served here:
///
///  * [TextNormalizer.normalizeKey] produces a canonical, length-*insensitive*
///    key used to compare terms (deduplicate dictionary entries, look entries
///    up). It may collapse whitespace and fold case.
///
///  * [TextNormalizer.normalizeToken] normalizes a single already-isolated
///    word *without* changing the relationship to source character offsets in
///    any way that matters for matching (it only lower-cases and unifies a few
///    punctuation variants, transforms that are 1:1 per code unit for the Latin
///    text we care about). The matcher tokenizes the original page text and
///    normalizes each token with this method, so reported match offsets still
///    line up with the PDF's per-character bounding boxes.
library;

/// Stateless helpers; grouped in a class purely for namespacing.
abstract final class TextNormalizer {
  /// Characters that are treated as equivalent to a straight apostrophe.
  static const _apostrophes = "'’ʼ‘`´";

  /// Characters treated as equivalent to an ASCII hyphen-minus.
  static const _hyphens = '-‐‑‒–—−';

  /// Normalize a single token (a "word"): lower-case and unify apostrophe and
  /// hyphen variants. Length is preserved for the scripts the app targets, so
  /// callers may keep using the token's original source offsets.
  static String normalizeToken(String token) {
    final buffer = StringBuffer();
    for (final rune in token.runes) {
      var ch = String.fromCharCode(rune);
      if (_apostrophes.contains(ch)) {
        ch = "'";
      } else if (_hyphens.contains(ch)) {
        ch = '-';
      }
      buffer.write(ch.toLowerCase());
    }
    return buffer.toString();
  }

  /// Normalize an arbitrary string into a canonical lookup/dedup key:
  /// trim, unify punctuation, lower-case, and collapse internal whitespace to
  /// single spaces.
  static String normalizeKey(String input) {
    final tokens = tokenize(input).map((t) => normalizeToken(t.text));
    return tokens.join(' ');
  }

  /// Split [input] into word tokens with their source offsets.
  ///
  /// A token is a maximal run of Unicode letters/digits, optionally joined by a
  /// single apostrophe or hyphen between two such runs (so `don't`,
  /// `well-known` and `café` are single tokens). Offsets are code-unit indices
  /// into [input], matching how Dart `String` and the PDF `charRects` list are
  /// indexed.
  static List<Token> tokenize(String input) {
    final result = <Token>[];
    for (final m in _tokenPattern.allMatches(input)) {
      result.add(Token(m.start, m.end, m.group(0)!));
    }
    return result;
  }

  /// The connector characters allowed inside a word, as a regex
  /// character-class body. The ASCII hyphen is escaped (`\-`) so it isn't
  /// interpreted as a range operator within the class.
  static const _wordConnectors = r"'’ʼ‘`´\-‐‑‒–—−";

  static final RegExp _tokenPattern = RegExp(
    '[\\p{L}\\p{N}]+(?:[$_wordConnectors][\\p{L}\\p{N}]+)*',
    unicode: true,
  );
}

/// A single word token and its half-open source range `[start, end)`.
class Token {
  const Token(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  @override
  String toString() => 'Token($start..$end "$text")';
}
