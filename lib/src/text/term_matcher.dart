import 'text_normalizer.dart';

/// A dictionary term prepared for matching: a sequence of normalized word
/// tokens plus the id of the owning dictionary entry.
class MatchableTerm {
  MatchableTerm(this.entryId, this.words, {this.partial = false});

  /// Build from a raw term string (e.g. "well-known fact").
  ///
  /// When [partial] is true and the term is a single word, the term will also
  /// match as a sub-word part of longer words (see [TermMatcher]). Partial
  /// matching is silently ignored for multi-word phrases.
  ///
  /// Returns `null` if the term contains no word tokens.
  static MatchableTerm? fromTerm(
    int entryId,
    String term, {
    bool partial = false,
  }) {
    final words = TextNormalizer.tokenize(
      term,
    ).map((t) => TextNormalizer.normalizeToken(t.text)).toList(growable: false);
    if (words.isEmpty) return null;
    return MatchableTerm(entryId, words, partial: partial && words.length == 1);
  }

  final int entryId;
  final List<String> words;

  /// Whether this (single-word) term matches sub-word parts of longer words.
  final bool partial;

  int get wordCount => words.length;
}

/// A located occurrence of a term inside a page's text, as a half-open source
/// range `[start, end)` of code-unit indices into the page's full text.
class TermMatch {
  const TermMatch(this.entryId, this.start, this.end);

  final int entryId;
  final int start;
  final int end;

  int get length => end - start;
}

/// In-memory whole-word / multi-word phrase matcher.
///
/// Matching is done on word boundaries (so "cat" does not match inside
/// "category") which is the right behaviour for a vocabulary highlighter. The
/// matcher tokenizes the page text and, at each token, checks whether any term
/// whose first word equals that token continues to match.
///
/// Construction is O(total term words); a single [findMatches] call is
/// O(page tokens * average candidates per first-word), which in practice is
/// close to linear because most first words have very few candidate terms.
class TermMatcher {
  TermMatcher(Iterable<MatchableTerm> terms) {
    for (final term in terms) {
      if (term.words.isEmpty) continue;
      // Partial single-word terms use the sub-word path below. (That path also
      // covers their whole-word occurrences, so they are not added to the
      // whole-word index as well — which would double-match.)
      if (term.partial && term.wordCount == 1) {
        _partialWords.add(term.words.first);
        _partialEntryIds.add(term.entryId);
        continue;
      }
      (_byFirstWord[term.words.first] ??= <MatchableTerm>[]).add(term);
      if (term.wordCount > _maxWords) _maxWords = term.wordCount;
    }
    // Longer phrases first so that, at a given position, the most specific
    // (longest) term is discovered before shorter ones.
    for (final list in _byFirstWord.values) {
      list.sort((a, b) => b.wordCount.compareTo(a.wordCount));
    }
  }

  final Map<String, List<MatchableTerm>> _byFirstWord = {};
  // Single-word sub-word terms, kept as parallel lists (word, entry id).
  final List<String> _partialWords = [];
  final List<int> _partialEntryIds = [];
  int _maxWords = 0;

  /// Whether the matcher has any terms at all.
  bool get isEmpty => _byFirstWord.isEmpty && _partialWords.isEmpty;

  /// The connectors a normalized token may contain (apostrophe / hyphen). A
  /// sub-word match is accepted when it abuts one of these or a token edge.
  static bool _isConnector(int codeUnit) =>
      codeUnit == 0x2D /* - */ || codeUnit == 0x27 /* ' */;

  /// Find every occurrence of every term in [text].
  ///
  /// Overlapping matches are all returned (e.g. both "bank" and "bank
  /// account"); callers decide how to render or prioritize overlaps.
  List<TermMatch> findMatches(String text) {
    if (isEmpty) return const [];
    final tokens = TextNormalizer.tokenize(text);
    final normalized = List<String>.generate(
      tokens.length,
      (i) => TextNormalizer.normalizeToken(tokens[i].text),
      growable: false,
    );
    final matches = <TermMatch>[];
    for (var i = 0; i < tokens.length; i++) {
      final candidates = _byFirstWord[normalized[i]];
      if (candidates == null) continue;
      for (final term in candidates) {
        final n = term.wordCount;
        if (i + n > tokens.length) continue;
        var ok = true;
        for (var k = 1; k < n; k++) {
          if (normalized[i + k] != term.words[k]) {
            ok = false;
            break;
          }
        }
        if (ok) {
          matches.add(
            TermMatch(term.entryId, tokens[i].start, tokens[i + n - 1].end),
          );
        }
      }
    }
    _findPartialMatches(tokens, normalized, matches);
    return matches;
  }

  /// Sub-word matching for partial single-word terms: a term matches wherever
  /// it occurs inside a token aligned to at least one sub-word boundary — the
  /// token's start/end, or next to a hyphen/apostrophe connector. So
  /// "perturbation" matches the prefix in "perturbations" and the
  /// hyphen-component in "small-perturbation", but not the interior of an
  /// unrelated word like "scatter".
  void _findPartialMatches(
    List<Token> tokens,
    List<String> normalized,
    List<TermMatch> out,
  ) {
    if (_partialWords.isEmpty) return;
    for (var i = 0; i < tokens.length; i++) {
      final tok = normalized[i];
      final tokLen = tok.length;
      final base = tokens[i].start;
      for (var w = 0; w < _partialWords.length; w++) {
        final word = _partialWords[w];
        final wlen = word.length;
        if (wlen == 0 || wlen > tokLen) continue;
        var from = 0;
        while (true) {
          final j = tok.indexOf(word, from);
          if (j < 0) break;
          final endIdx = j + wlen;
          final leftOk = j == 0 || _isConnector(tok.codeUnitAt(j - 1));
          final rightOk =
              endIdx == tokLen || _isConnector(tok.codeUnitAt(endIdx));
          if (leftOk || rightOk) {
            out.add(TermMatch(_partialEntryIds[w], base + j, base + endIdx));
          }
          from = j + 1;
        }
      }
    }
  }

  /// Largest word count among the loaded terms (useful for diagnostics).
  int get maxPhraseWordCount => _maxWords;
}
