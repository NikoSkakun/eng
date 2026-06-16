import 'package:eng/src/text/term_matcher.dart';
import 'package:eng/src/text/text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextNormalizer', () {
    test('normalizeKey lower-cases, trims and collapses whitespace', () {
      expect(TextNormalizer.normalizeKey('  The   Quick  '), 'the quick');
    });

    test('unifies apostrophe and hyphen variants', () {
      expect(TextNormalizer.normalizeToken('don’t'), "don't");
      expect(TextNormalizer.normalizeToken('well‑known'), 'well-known');
    });

    test('tokenize reports correct source offsets', () {
      const text = 'a cat sat';
      final tokens = TextNormalizer.tokenize(text);
      expect(tokens.map((t) => t.text).toList(), ['a', 'cat', 'sat']);
      expect(text.substring(tokens[1].start, tokens[1].end), 'cat');
    });

    test('keeps intra-word apostrophes and hyphens as one token', () {
      expect(TextNormalizer.tokenize("don't").length, 1);
      expect(TextNormalizer.tokenize('well-known').length, 1);
    });

    test('trimEdgePunctuation strips edge punctuation, keeps inner', () {
      expect(TextNormalizer.trimEdgePunctuation('oblate,'), 'oblate');
      expect(TextNormalizer.trimEdgePunctuation('(don\'t).'), "don't");
      expect(TextNormalizer.trimEdgePunctuation('"word"'), 'word');
      expect(TextNormalizer.trimEdgePunctuation('well-known'), 'well-known');
      expect(TextNormalizer.trimEdgePunctuation('“café”!'), 'café');
      expect(TextNormalizer.trimEdgePunctuation('...'), '');
    });
  });

  group('TermMatcher', () {
    TermMatcher build(Map<int, String> terms) => TermMatcher(
      terms.entries.map((e) => MatchableTerm.fromTerm(e.key, e.value)!),
    );

    test('matches whole words only (not substrings)', () {
      final m = build({1: 'cat'});
      const text = 'The cat sat. Category is different.';
      final matches = m.findMatches(text);
      expect(matches.length, 1);
      expect(text.substring(matches.first.start, matches.first.end), 'cat');
      expect(matches.first.entryId, 1);
    });

    test('is case-insensitive', () {
      final m = build({1: 'cat'});
      final matches = m.findMatches('CAT Cat cat');
      expect(matches.length, 3);
    });

    test('matches multi-word phrases across arbitrary whitespace', () {
      final m = build({2: 'bank account'});
      const text = 'My bank   account number.';
      final matches = m.findMatches(text);
      expect(matches.length, 1);
      final matched = text.substring(matches.first.start, matches.first.end);
      expect(matched.replaceAll(RegExp(r'\s+'), ' '), 'bank account');
      expect(matches.first.entryId, 2);
    });

    test('finds all occurrences', () {
      final m = build({1: 'the'});
      final matches = m.findMatches('the cat and the dog and the bird');
      expect(matches.length, 3);
    });

    test('returns both overlapping terms when present', () {
      final m = build({1: 'bank', 2: 'bank account'});
      final matches = m.findMatches('a bank account');
      expect(matches.map((e) => e.entryId).toSet(), {1, 2});
    });

    test('handles apostrophes in terms and text', () {
      final m = build({3: "don't"});
      final matches = m.findMatches('I don’t know');
      expect(matches.length, 1);
    });

    test('empty matcher returns nothing', () {
      expect(TermMatcher(const []).findMatches('anything'), isEmpty);
    });
  });

  group('TermMatcher sub-word (partial) matching', () {
    TermMatcher partial(Map<int, String> terms) => TermMatcher(
      terms.entries.map(
        (e) => MatchableTerm.fromTerm(e.key, e.value, partial: true)!,
      ),
    );

    test('matches the prefix inside a longer (inflected) word', () {
      final m = partial({1: 'perturbation'});
      const text = 'small perturbations occur';
      final matches = m.findMatches(text);
      expect(matches.length, 1);
      expect(
        text.substring(matches.first.start, matches.first.end),
        'perturbation',
      );
    });

    test('matches a hyphen-delimited component of a compound', () {
      final m = partial({1: 'perturbation'});
      const text = 'a small-perturbation model';
      final matches = m.findMatches(text);
      expect(matches.length, 1);
      expect(
        text.substring(matches.first.start, matches.first.end),
        'perturbation',
      );
    });

    test('still matches the standalone whole word (no double match)', () {
      final m = partial({1: 'perturbation'});
      final matches = m.findMatches('the perturbation is small');
      expect(matches.length, 1);
    });

    test('does not match an unrelated interior substring', () {
      // "cat" sits between letters in "scatter": no aligned boundary.
      final m = partial({1: 'cat'});
      expect(m.findMatches('scattered locations'), isEmpty);
    });

    test('a non-partial term never matches sub-words (default behaviour)', () {
      final m = TermMatcher([MatchableTerm.fromTerm(1, 'perturbation')!]);
      expect(m.findMatches('perturbations and small-perturbation'), isEmpty);
    });

    test('the partial flag is ignored for multi-word phrases', () {
      final m = TermMatcher([
        MatchableTerm.fromTerm(1, 'bank account', partial: true)!,
      ]);
      // Still whole-word phrase matching: "accounts" is not "account".
      expect(m.findMatches('my bank accounts'), isEmpty);
      expect(m.findMatches('my bank account here').length, 1);
    });

    test('matches multiple sub-word occurrences across the text', () {
      final m = partial({1: 'form'});
      // "forms" (prefix) and "trans-form" (hyphen component) both count.
      final matches = m.findMatches('forms and trans-form');
      expect(matches.length, 2);
    });
  });
}
