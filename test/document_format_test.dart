import 'package:eng/src/models/document_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('documentFormatForPath', () {
    test('maps known extensions', () {
      expect(documentFormatForPath('/a/b.pdf'), DocumentFormat.pdf);
      expect(documentFormatForPath('book.EPUB'), DocumentFormat.epub);
      expect(documentFormatForPath('book.mobi'), DocumentFormat.mobi);
      expect(documentFormatForPath('book.azw3'), DocumentFormat.mobi);
      expect(documentFormatForPath('book.prc'), DocumentFormat.mobi);
      expect(documentFormatForPath('book.fb2'), DocumentFormat.fb2);
      expect(documentFormatForPath('notes.txt'), DocumentFormat.txt);
      expect(documentFormatForPath('page.html'), DocumentFormat.html);
      expect(documentFormatForPath('readme.md'), DocumentFormat.markdown);
      expect(documentFormatForPath('doc.rtf'), DocumentFormat.rtf);
    });

    test('unknown extension and dotless names', () {
      expect(documentFormatForPath('archive.zip'), DocumentFormat.unknown);
      // A dot only in the directory, not the filename, is not an extension.
      expect(documentFormatForPath('/a.b/README'), DocumentFormat.unknown);
    });

    test('isReflowable is true for everything but pdf/unknown', () {
      expect(DocumentFormat.pdf.isReflowable, isFalse);
      expect(DocumentFormat.unknown.isReflowable, isFalse);
      expect(DocumentFormat.epub.isReflowable, isTrue);
      expect(DocumentFormat.txt.isReflowable, isTrue);
    });

    test('isSupportedImportPath', () {
      expect(isSupportedImportPath('a.epub'), isTrue);
      expect(isSupportedImportPath('a.pdf'), isTrue);
      expect(isSupportedImportPath('a.zip'), isFalse);
      expect(isSupportedImportPath('noext'), isFalse);
    });
  });
}
