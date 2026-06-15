import 'text_normalizer.dart';

/// A dictionary term prepared for matching: a sequence of normalized word
/// tokens plus the id of the owning dictionary entry.
class MatchableTerm {
  MatchableTerm(this.entryId, this.words);

  /// Build from a raw term string (e.g. "well-known fact").
  ///
  /// Returns `null` if the term contains no word tokens.
  static MatchableTerm? fromTerm(int entryId, String term) {
    final words = TextNormalizer.tokenize(
      term,
    ).map((t) => TextNormalizer.normalizeToken(t.text)).toList(growable: false);
    if (words.isEmpty) return null;
    return MatchableTerm(entryId, words);
  }

  final int entryId;
  final List<String> words;

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
  int _maxWords = 0;

  /// Whether the matcher has any terms at all.
  bool get isEmpty => _byFirstWord.isEmpty;

  /// Find every occurrence of every term in [text].
  ///
  /// Overlapping matches are all returned (e.g. both "bank" and "bank
  /// account"); callers decide how to render or prioritize overlaps.
  List<TermMatch> findMatches(String text) {
    if (_byFirstWord.isEmpty) return const [];
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
    return matches;
  }

  /// Largest word count among the loaded terms (useful for diagnostics).
  int get maxPhraseWordCount => _maxWords;
}
