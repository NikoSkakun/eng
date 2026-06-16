import 'package:eng/src/text/text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextNormalizer.joinWrappedLines', () {
    String join(String s) => TextNormalizer.joinWrappedLines(s);

    test('rejoins a word hyphenated across a line break', () {
      expect(join('undis-\nturbed'), 'undisturbed');
      expect(join('inter-\nnational waters'), 'international waters');
    });

    test('handles trailing/leading spaces around the hyphen break', () {
      expect(join('undis-  \n  turbed'), 'undisturbed');
    });

    test('turns line breaks into single spaces', () {
      expect(join('first line\nsecond line'), 'first line second line');
      expect(join('a\r\nb'), 'a b');
    });

    test('collapses blank lines / paragraph breaks to one space', () {
      expect(join('para one\n\npara two'), 'para one para two');
    });

    test('keeps a genuine compound split before a capitalised word', () {
      // Not soft hyphenation — the hyphen is preserved, the newline becomes a
      // space (we do not merge "Known" onto "well").
      expect(join('well-\nKnown'), 'well- Known');
    });

    test('does not merge across an en/em dash (punctuation, not a word break)',
        () {
      expect(join('foo —\nbar'), 'foo — bar');
      expect(join('foo –\nbar'), 'foo – bar');
    });

    test('leaves single-line text untouched', () {
      expect(join('already continuous'), 'already continuous');
      expect(join(''), '');
    });

    test('rejoins a soft-hyphen line break', () {
      expect(join('co­\noperate'), 'cooperate');
    });

    test("rejoins PDFium's U+0002 line-break hyphen marker (no newline)", () {
      // PDFium delivers the line-break hyphen as U+0002, with the word halves
      // adjacent and no newline — the real-world case the user hit.
      expect(join('undis\u0002turbed'), 'undisturbed');
      expect(join('inter\u0002national waters'), 'international waters');
    });

    test('rejoins a U+0002 marker even when a newline follows it', () {
      expect(join('undis\u0002\nturbed'), 'undisturbed');
      expect(join('undis\u0002\r\nturbed'), 'undisturbed');
    });

    test('leaves a real hyphen mid-line intact (not a line break)', () {
      expect(join('well-known fact'), 'well-known fact');
    });
  });
}
