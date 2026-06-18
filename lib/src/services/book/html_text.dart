import 'dart:convert';
import 'dart:typed_data';

import 'book_content.dart';

/// Shared helpers for turning raw bytes / HTML markup into the flowing
/// [BookBlock]s used by the text reader. Used by the EPUB, MOBI, FB2, HTML,
/// Markdown and plain-text parsers.

/// Decode [bytes] into a Dart string, honouring a BOM and falling back
/// gracefully. [codepage] is a hint from formats that record one (e.g. MOBI):
/// 1252 forces a Windows-1252/Latin-1 decode; 0 means "detect".
String decodeBytes(Uint8List bytes, {int codepage = 0}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), little: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), little: false);
  }
  if (codepage == 1252) {
    return latin1.decode(bytes, allowInvalid: true);
  }
  // Default: prefer strict UTF-8, but fall back to Latin-1 for legacy files.
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes, allowInvalid: true);
  }
}

String _decodeUtf16(List<int> bytes, {required bool little}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      little ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

/// A small set of named HTML entities beyond the numeric ones.
const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'lsquo': '‘',
  'rsquo': '’',
  'ldquo': '“',
  'rdquo': '”',
  'laquo': '«',
  'raquo': '»',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'deg': '°',
  'middot': '·',
  'bull': '•',
  'shy': '',
};

final RegExp _entityPattern =
    RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');

/// Decode numeric (`&#233;`, `&#xE9;`) and common named HTML entities.
String decodeHtmlEntities(String input) {
  return input.replaceAllMapped(_entityPattern, (m) {
    final body = m[1]!;
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final code = int.tryParse(body.substring(2), radix: 16);
      return code == null ? m[0]! : _safeChar(code);
    }
    if (body.startsWith('#')) {
      final code = int.tryParse(body.substring(1));
      return code == null ? m[0]! : _safeChar(code);
    }
    return _entities[body] ?? _entities[body.toLowerCase()] ?? m[0]!;
  });
}

String _safeChar(int code) {
  if (code <= 0 || code > 0x10FFFF) return '';
  try {
    return String.fromCharCode(code);
  } catch (_) {
    return '';
  }
}

final RegExp _commentRe = RegExp(r'<!--.*?-->', dotAll: true);
final RegExp _scriptRe =
    RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false);
final RegExp _styleRe =
    RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false);
final RegExp _headRe =
    RegExp(r'<head[^>]*>.*?</head>', dotAll: true, caseSensitive: false);
final RegExp _headingRe = RegExp(
  r'<h[1-6][^>]*>(.*?)</h[1-6]>',
  dotAll: true,
  caseSensitive: false,
);
final RegExp _brRe = RegExp(r'<br\s*/?>', caseSensitive: false);
final RegExp _blockCloseRe = RegExp(
  r'</(p|div|li|tr|h[1-6]|blockquote|section|article|figure|'
  r'figcaption|pre|td|ul|ol|table|hr)\s*>',
  caseSensitive: false,
);
final RegExp _blockOpenRe = RegExp(
  r'<(p|div|li|tr|blockquote|section|article|figure|pre|hr)[^>]*>',
  caseSensitive: false,
);
final RegExp _tagRe = RegExp(r'<[^>]+>');
final RegExp _wsRe = RegExp('[ \t\u00a0]+');

// A private sentinel used to carry "this line is a heading" through the plain
// stripping pass (the char never appears in real text).
const String _headingMark = '\u0001';

/// Convert an HTML/XHTML fragment into ordered [BookBlock]s. Block-level tags
/// become paragraph breaks, `<h1>`-`<h6>` become headings, and entities are
/// decoded. Tolerant of malformed markup (no DOM required), which matters for
/// the loosely-structured XHTML inside many EPUB/MOBI files.
List<BookBlock> htmlToBlocks(String html) {
  var s = html;
  s = s.replaceAll(_commentRe, ' ');
  s = s.replaceAll(_scriptRe, ' ');
  s = s.replaceAll(_styleRe, ' ');
  s = s.replaceAll(_headRe, ' ');
  s = s.replaceAllMapped(
    _headingRe,
    (m) => '\n$_headingMark${m[1]}$_headingMark\n',
  );
  s = s.replaceAll(_brRe, '\n');
  s = s.replaceAll(_blockCloseRe, '\n');
  s = s.replaceAll(_blockOpenRe, '\n');
  s = s.replaceAll(_tagRe, '');
  s = decodeHtmlEntities(s);

  final blocks = <BookBlock>[];
  for (var line in s.split('\n')) {
    var heading = false;
    if (line.contains(_headingMark)) {
      heading = true;
      line = line.replaceAll(_headingMark, '');
    }
    line = line.replaceAll('\r', '').replaceAll(_wsRe, ' ').trim();
    if (line.isEmpty) continue;
    blocks.add(BookBlock(line, heading: heading));
  }
  return blocks;
}

/// Split already-decoded plain text into paragraph [BookBlock]s on blank lines,
/// collapsing soft-wrapped lines within a paragraph into a single run.
List<BookBlock> plainTextToBlocks(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final paras = normalized.split(RegExp(r'\n[ \t]*\n'));
  final blocks = <BookBlock>[];
  for (final para in paras) {
    final t = para
        .replaceAll(RegExp(r'\s*\n\s*'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .trim();
    if (t.isNotEmpty) blocks.add(BookBlock(t));
  }
  if (blocks.isEmpty && text.trim().isNotEmpty) {
    blocks.add(BookBlock(text.trim()));
  }
  return blocks;
}
