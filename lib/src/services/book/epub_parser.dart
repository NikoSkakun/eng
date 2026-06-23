import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'book_content.dart';
import 'html_text.dart';

/// Parse an EPUB (a ZIP of XHTML documents described by an OPF package file).
///
/// EPUB structure: `META-INF/container.xml` points at the OPF package document,
/// whose `<manifest>` maps ids to files and whose `<spine>` lists those ids in
/// reading order. We read each spine document, strip its XHTML to text, and
/// concatenate.
BookContent parseEpub(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const BookFormatException('This EPUB file could not be opened.');
  }

  String? read(String name) {
    final f =
        archive.findFile(name) ?? archive.findFile(_stripLeadingSlash(name));
    final b = f?.readBytes();
    return b == null ? null : decodeBytes(Uint8List.fromList(b));
  }

  final containerXml = read('META-INF/container.xml');
  if (containerXml == null) {
    throw const BookFormatException(
      'Not a valid EPUB (missing container.xml).',
    );
  }
  final opfPath = _firstAttr(
    XmlDocument.parse(containerXml),
    'rootfile',
    'full-path',
  );
  if (opfPath == null) {
    throw const BookFormatException('EPUB has no package document.');
  }
  final opfStr = read(opfPath);
  if (opfStr == null) {
    throw const BookFormatException('EPUB package document is missing.');
  }

  final opf = XmlDocument.parse(opfStr);
  final baseDir = p.url.dirname(opfPath);

  // manifest: id -> href (+ media-type)
  final manifest = <String, String>{};
  for (final item in _byLocalName(opf, 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) manifest[id] = href;
  }

  // spine: ordered list of manifest item ids
  final spine = <String>[];
  for (final ref in _byLocalName(opf, 'itemref')) {
    final idref = ref.getAttribute('idref');
    if (idref != null && manifest.containsKey(idref)) {
      spine.add(manifest[idref]!);
    }
  }

  final blocks = <BookBlock>[];
  for (final href in spine) {
    final clean = Uri.decodeFull(href.split('#').first);
    final full = baseDir == '.' || baseDir.isEmpty
        ? clean
        : p.url.normalize(p.url.join(baseDir, clean));
    final html = read(full) ?? read(clean);
    if (html == null) continue;
    blocks.addAll(htmlToBlocks(html));
  }

  if (blocks.isEmpty) {
    throw const BookFormatException('This EPUB contained no readable text.');
  }

  String? title;
  for (final t in _byLocalName(opf, 'title')) {
    final s = t.innerText.trim();
    if (s.isNotEmpty) {
      title = s;
      break;
    }
  }
  return BookContent(blocks: blocks, title: title);
}

String _stripLeadingSlash(String s) => s.startsWith('/') ? s.substring(1) : s;

/// All [XmlElement]s in [doc] whose local (namespace-stripped) name matches.
Iterable<XmlElement> _byLocalName(XmlDocument doc, String local) =>
    doc.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String? _firstAttr(XmlDocument doc, String local, String attr) {
  for (final e in _byLocalName(doc, local)) {
    final v = e.getAttribute(attr);
    if (v != null) return v;
  }
  return null;
}
