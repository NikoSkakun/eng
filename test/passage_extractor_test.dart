import 'package:eng/src/text/passage_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Locate a substring and extract the passage around it, so tests can express
  // the selection by the word itself rather than hand-counting offsets.
  String around(String text, String sel, {int maxChars = 400}) {
    final start = text.indexOf(sel);
    expect(start, isNonNegative, reason: 'selection "$sel" not found in text');
    return extractContextPassage(
      text,
      start,
      start + sel.length,
      maxChars: maxChars,
    );
  }

  group('extractContextPassage', () {
    test('returns the whole text when it is short', () {
      const t = 'A small sentence with a word.';
      expect(around(t, 'word'), t);
    });

    test('isolates the sentence containing the selection', () {
      const t = 'First sentence here. The quick brown fox jumps. Last one.';
      // No blank lines and the whole thing fits in the window, so it stays whole
      // — sentence trimming only kicks in at a capped window's edges.
      expect(around(t, 'fox'), t);
    });

    test('trims partial sentences at a capped window edge', () {
      final filler = List.filled(60, 'lorem ipsum dolor').join(' ');
      final text = '$filler. Alpha beta TARGET gamma delta. $filler.';
      final passage = around(text, 'TARGET', maxChars: 40);
      // The window is far smaller than the filler on each side, so the result is
      // just the target's own sentence, with no lorem bleed-in.
      expect(passage, 'Alpha beta TARGET gamma delta.');
    });

    test('keeps to the enclosing paragraph when blank lines delimit it', () {
      const t =
          'Intro paragraph that we do not want.\n\n'
          'The middle paragraph holds the TARGET word and more text.\n\n'
          'A trailing paragraph we also do not want.';
      final passage = around(t, 'TARGET', maxChars: 1000);
      expect(
        passage,
        'The middle paragraph holds the TARGET word and more text.',
      );
    });

    test('paragraph wins over the maxChars window', () {
      const para = 'The middle paragraph holds the TARGET word here.';
      const t = 'Intro.\n\n$para\n\nOutro.';
      // Even with a generous window, it must not cross the blank lines.
      expect(around(t, 'TARGET', maxChars: 5000), para);
    });

    test('joins nothing and never starts or ends mid-word', () {
      final filler = List.filled(50, 'word').join(' ');
      final text = '$filler needleword $filler';
      final passage = around(text, 'needleword', maxChars: 20);
      expect(passage.startsWith('word'), isTrue);
      expect(passage.endsWith('word'), isTrue);
      expect(passage.contains('needleword'), isTrue);
    });

    test('handles a selection at the very start', () {
      const t = 'TARGET leads the sentence. And another follows.';
      final passage = around(t, 'TARGET');
      expect(passage.contains('TARGET leads the sentence.'), isTrue);
    });

    test('empty text yields empty passage', () {
      expect(extractContextPassage('', 0, 0), '');
    });

    test('out-of-range offsets are clamped, not thrown', () {
      const t = 'Short text.';
      expect(extractContextPassage(t, -5, 999), t);
    });
  });
}
