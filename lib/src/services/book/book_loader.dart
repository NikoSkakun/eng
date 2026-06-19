import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/document_format.dart';
import 'book_content.dart';
import 'epub_parser.dart';
import 'fb2_parser.dart';
import 'html_text.dart';
import 'mobi_parser.dart';

/// Load and parse a reflowable document into [BookContent].
///
/// Parsing (file read + decompression + HTML stripping) runs on a background
/// isolate via [compute] so large books never block the UI thread.
Future<BookContent> loadBook(String path, DocumentFormat format) {
  return compute(_loadBookEntry, _BookRequest(path, format.name));
}

class _BookRequest {
  const _BookRequest(this.path, this.format);
  final String path;
  final String format;
}

BookContent _loadBookEntry(_BookRequest req) {
  final format = DocumentFormat.values.firstWhere(
    (f) => f.name == req.format,
    orElse: () => DocumentFormat.txt,
  );
  final Uint8List bytes;
  try {
    bytes = File(req.path).readAsBytesSync();
  } catch (_) {
    throw const BookFormatException('The file could not be read.');
  }

  switch (format) {
    case DocumentFormat.epub:
      return parseEpub(bytes);
    case DocumentFormat.mobi:
      return parseMobi(bytes);
    case DocumentFormat.fb2:
      return parseFb2(decodeBytes(bytes));
    case DocumentFormat.html:
      final blocks = htmlToBlocks(decodeBytes(bytes));
      if (blocks.isEmpty) {
        throw const BookFormatException('This file contained no readable text.');
      }
      return BookContent(blocks: blocks);
    case DocumentFormat.markdown:
      return _parseMarkdown(decodeBytes(bytes));
    case DocumentFormat.rtf:
      return _parseRtf(decodeBytes(bytes));
    case DocumentFormat.txt:
    case DocumentFormat.pdf:
    case DocumentFormat.unknown:
      return BookContent(blocks: plainTextToBlocks(decodeBytes(bytes)));
  }
}

// --- Markdown (lightweight: headings + paragraphs, markup stripped) ---------

final RegExp _mdHeading = RegExp(r'^(#{1,6})\s+(.*)$');

BookContent _parseMarkdown(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final blocks = <BookBlock>[];
  final buf = StringBuffer();

  void flush() {
    final t = buf.toString().trim();
    if (t.isNotEmpty) blocks.add(BookBlock(_stripMarkdown(t)));
    buf.clear();
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    final h = _mdHeading.firstMatch(line);
    if (h != null) {
      flush();
      blocks.add(BookBlock(_stripMarkdown(h.group(2)!.trim()), heading: true));
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
    } else {
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(line.trim());
    }
  }
  flush();

  if (blocks.isEmpty && text.trim().isNotEmpty) {
    blocks.add(BookBlock(text.trim()));
  }
  return BookContent(blocks: blocks);
}

String _stripMarkdown(String s) {
  var r = s;
  r = r.replaceAll(RegExp(r'`{1,3}'), '');
  r = r.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
  r = r.replaceAll(RegExp(r'[*_]{1,3}'), '');
  r = r.replaceAll(RegExp(r'^\s{0,3}>\s?'), '');
  r = r.replaceAll(RegExp(r'^\s{0,3}[-*+]\s+'), '');
  return r.trim();
}

// --- RTF (best-effort: strip control words and groups) ----------------------

BookContent _parseRtf(String rtf) {
  var s = rtf;
  s = s.replaceAll(RegExp(r'\\par[d]?\b'), '\n');
  s = s.replaceAll(RegExp(r'\\line\b'), '\n');
  // Drop whole control groups for font/colour/stylesheet tables etc.
  s = s.replaceAll(RegExp(r'\{\\\*?[^{}]*\}'), ' ');
  // \uN unicode escapes.
  s = s.replaceAllMapped(RegExp(r"\\u(-?\d+)\s?\??"), (m) {
    final c = int.tryParse(m[1]!);
    return c == null ? '' : String.fromCharCode(c & 0xFFFF);
  });
  // \'xx hex escapes.
  s = s.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"), (m) {
    return String.fromCharCode(int.parse(m[1]!, radix: 16));
  });
  // Remaining control words and braces.
  s = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
  s = s.replaceAll(RegExp(r'[{}]'), '');
  return BookContent(blocks: plainTextToBlocks(s));
}
