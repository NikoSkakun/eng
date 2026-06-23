import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:eng/src/services/book/book_content.dart';
import 'package:eng/src/services/book/epub_parser.dart';
import 'package:eng/src/services/book/fb2_parser.dart';
import 'package:eng/src/services/book/html_text.dart';
import 'package:eng/src/services/book/mobi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('htmlToBlocks', () {
    test('splits block tags, extracts headings, decodes entities', () {
      final blocks = htmlToBlocks(
        '<html><head><title>x</title></head><body>'
        '<h1>Chapter &amp; One</h1>'
        '<p>Hello&nbsp;world.</p>'
        '<p>Second &#233; paragraph.<br/>same paragraph line.</p>'
        '<script>ignore()</script>'
        '</body></html>',
      );
      expect(blocks.length, 4);
      expect(blocks[0].heading, isTrue);
      expect(blocks[0].text, 'Chapter & One');
      expect(blocks[1].heading, isFalse);
      expect(blocks[1].text, 'Hello world.');
      expect(blocks[2].text, 'Second é paragraph.');
      expect(blocks[3].text, 'same paragraph line.');
    });

    test('strips style blocks and unknown inline tags', () {
      final blocks = htmlToBlocks(
        '<style>p{color:red}</style><p>A <b>bold</b> word</p>',
      );
      expect(blocks.length, 1);
      expect(blocks.single.text, 'A bold word');
    });
  });

  group('plainTextToBlocks', () {
    test('paragraphs split on blank lines, soft wraps joined', () {
      final blocks = plainTextToBlocks(
        'First line\nstill first.\n\nSecond paragraph.\n',
      );
      expect(blocks.length, 2);
      expect(blocks[0].text, 'First line still first.');
      expect(blocks[1].text, 'Second paragraph.');
    });
  });

  group('parseFb2', () {
    test('reads titles and paragraphs from the body', () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
  <description><title-info><book-title>My Book</book-title></title-info></description>
  <body>
    <title><p>Chapter One</p></title>
    <section>
      <p>The quick brown fox.</p>
      <p>Jumped over.</p>
    </section>
  </body>
</FictionBook>''';
      final book = parseFb2(xml);
      expect(book.title, 'My Book');
      final headings = book.blocks.where((b) => b.heading).map((b) => b.text);
      expect(headings, contains('Chapter One'));
      final paras = book.blocks
          .where((b) => !b.heading)
          .map((b) => b.text)
          .toList();
      expect(paras, containsAll(['The quick brown fox.', 'Jumped over.']));
    });
  });

  group('parseEpub', () {
    test('reads spine documents in order with title', () {
      final bytes = _buildEpub();
      final book = parseEpub(bytes);
      expect(book.title, 'Test Book');
      expect(book.blocks.first.heading, isTrue);
      expect(book.blocks.first.text, 'Greeting');
      expect(
        book.blocks.map((b) => b.text),
        contains('Hello from the first chapter.'),
      );
    });

    test('throws a friendly error on a non-epub zip', () {
      final archive = Archive()
        ..addFile(ArchiveFile.string('hello.txt', 'not an epub'));
      final bytes = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
      expect(() => parseEpub(bytes), throwsA(isA<BookFormatException>()));
    });
  });

  group('parseMobi', () {
    test('parses a minimal PalmDOC MOBI into blocks', () {
      final bytes = _buildMobi(
        '<h1>Title</h1><p>Hello world. The cat sat.</p>',
      );
      final book = parseMobi(bytes);
      expect(book.blocks.first.heading, isTrue);
      expect(book.blocks.first.text, 'Title');
      expect(
        book.blocks.map((b) => b.text),
        contains('Hello world. The cat sat.'),
      );
    });

    test('throws on a too-small / invalid file', () {
      expect(
        () => parseMobi(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<BookFormatException>()),
      );
    });
  });
}

Uint8List _buildEpub() {
  const container =
      '<?xml version="1.0"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  const opf =
      '<?xml version="1.0"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
      'unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>Test Book</dc:title></metadata>'
      '<manifest>'
      '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest>'
      '<spine><itemref idref="c1"/></spine></package>';
  const chapter =
      '<html><body><h1>Greeting</h1>'
      '<p>Hello from the first chapter.</p></body></html>';

  final archive = Archive()
    ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'))
    ..addFile(ArchiveFile.string('META-INF/container.xml', container))
    ..addFile(ArchiveFile.string('OEBPS/content.opf', opf))
    ..addFile(ArchiveFile.string('OEBPS/chapter1.xhtml', chapter));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// Build a minimal uncompressed-text MOBI/PDB with one PalmDOC text record.
/// The text is pure ASCII (>= 0x20), so PalmDOC "compression" with each byte as
/// a literal round-trips it unchanged — exercising the decompressor's literal
/// path and the PDB record plumbing.
Uint8List _buildMobi(String text) {
  final textBytes = Uint8List.fromList(text.codeUnits);
  const numRecords = 2;
  final headerLen = 78 + numRecords * 8;
  const palmDocHeaderLen = 16;
  final rec0Offset = headerLen;
  final rec1Offset = rec0Offset + palmDocHeaderLen;
  final total = rec1Offset + textBytes.length;

  final out = Uint8List(total);
  final bd = ByteData.sublistView(out);

  // PDB header type/creator (cosmetic) and record count.
  out.setRange(60, 64, 'BOOK'.codeUnits);
  out.setRange(64, 68, 'MOBI'.codeUnits);
  bd.setUint16(76, numRecords);

  // Record-info entries.
  bd.setUint32(78, rec0Offset);
  bd.setUint32(78 + 8, rec1Offset);

  // PalmDOC header in record 0: compression=2 (PalmDOC), textLength, 1 record.
  bd.setUint16(rec0Offset, 2);
  bd.setUint32(rec0Offset + 4, textBytes.length);
  bd.setUint16(rec0Offset + 8, 1);
  bd.setUint16(rec0Offset + 10, 4096);

  out.setRange(rec1Offset, total, textBytes);
  return out;
}
