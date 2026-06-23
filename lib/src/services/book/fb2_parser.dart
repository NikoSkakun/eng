import 'package:xml/xml.dart';

import 'book_content.dart';

/// Parse a FictionBook 2 (.fb2) file: an XML format whose `<body>` holds nested
/// `<section>`s of `<title>` headings and `<p>` paragraphs.
BookContent parseFb2(String xmlString) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xmlString);
  } catch (_) {
    throw const BookFormatException('This FB2 file could not be parsed.');
  }

  final blocks = <BookBlock>[];
  for (final body in doc.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'body',
  )) {
    _walk(body, blocks);
  }

  if (blocks.isEmpty) {
    throw const BookFormatException(
      'This FB2 file contained no readable text.',
    );
  }

  String? title;
  for (final e in doc.descendants.whereType<XmlElement>()) {
    if (e.name.local == 'book-title') {
      final s = _clean(e.innerText);
      if (s.isNotEmpty) title = s;
      break;
    }
  }
  return BookContent(blocks: blocks, title: title);
}

void _walk(XmlElement el, List<BookBlock> out) {
  for (final node in el.children) {
    if (node is! XmlElement) continue;
    switch (node.name.local) {
      case 'title':
        final t = _clean(node.innerText);
        if (t.isNotEmpty) out.add(BookBlock(t, heading: true));
      case 'p':
      case 'subtitle':
      case 'v': // a line of verse
        final t = _clean(node.innerText);
        if (t.isNotEmpty) out.add(BookBlock(t));
      case 'section':
      case 'epigraph':
      case 'cite':
      case 'annotation':
      case 'poem':
      case 'stanza':
        _walk(node, out);
      default:
        break; // skip images, binaries, etc.
    }
  }
}

final RegExp _ws = RegExp(r'\s+');
String _clean(String s) => s.replaceAll(_ws, ' ').trim();
