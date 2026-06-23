import 'dart:typed_data';

import 'book_content.dart';
import 'html_text.dart';

/// Parse a MOBI / older Kindle (.mobi, .azw, .prc) book.
///
/// A MOBI is a Palm Database (PDB) whose first record holds a PalmDOC + MOBI
/// header; the following records hold the book text, PalmDOC-compressed and
/// concatenated. The decompressed text is HTML-ish, so it is run through the
/// shared HTML stripper. HUFF/CDIC-compressed books are detected and reported
/// rather than mis-decoded.
BookContent parseMobi(Uint8List data) {
  if (data.length < 78) {
    throw const BookFormatException('File is too small to be a MOBI book.');
  }
  final bd = ByteData.sublistView(data);

  final numRecords = bd.getUint16(76);
  if (numRecords == 0 || data.length < 78 + numRecords * 8) {
    throw const BookFormatException('Not a valid MOBI/PRC file.');
  }

  // PDB record offsets (each record-info entry is 8 bytes from offset 78).
  final offsets = <int>[];
  for (var i = 0; i < numRecords; i++) {
    offsets.add(bd.getUint32(78 + i * 8));
  }
  offsets.add(data.length); // sentinel end-of-last-record

  final rec0Start = offsets[0];
  final rec0End = offsets[1];
  if (rec0Start < 0 || rec0End > data.length || rec0Start + 16 > rec0End) {
    throw const BookFormatException('MOBI header is corrupt.');
  }

  // PalmDOC header (start of record 0).
  final compression = bd.getUint16(rec0Start);
  final textLength = bd.getUint32(rec0Start + 4);
  final recordCount = bd.getUint16(rec0Start + 8);

  // MOBI header (immediately after the 16-byte PalmDOC header).
  var encoding = 1252;
  var extraFlags = 0;
  if (rec0Start + 20 <= rec0End && _ascii(data, rec0Start + 16, 4) == 'MOBI') {
    final mobiHeaderLen = bd.getUint32(rec0Start + 20);
    if (rec0Start + 32 <= rec0End) {
      encoding = bd.getUint32(rec0Start + 28);
    }
    // "Extra data flags" live at offset 0xF2 in record 0 on newer headers.
    if (mobiHeaderLen >= 0xE4 && rec0Start + 0xF2 + 2 <= rec0End) {
      extraFlags = bd.getUint16(rec0Start + 0xF2);
    }
  }

  if (compression == 17480) {
    throw const BookFormatException(
      'This MOBI uses HUFF/CDIC compression, which is not supported yet. '
      'Try converting it to EPUB.',
    );
  }

  final out = BytesBuilder();
  final lastTextRecord = recordCount < numRecords - 1
      ? recordCount
      : numRecords - 1;
  for (var i = 1; i <= lastTextRecord; i++) {
    final start = offsets[i];
    final end = offsets[i + 1];
    if (start < 0 || end > data.length || start >= end) continue;
    var rec = Uint8List.sublistView(data, start, end);
    rec = _stripTrailing(rec, extraFlags);
    if (rec.isEmpty) continue;
    if (compression == 2) {
      out.add(_palmDocDecompress(rec));
    } else {
      out.add(rec); // 1 = uncompressed
    }
  }

  var textBytes = out.toBytes();
  if (textLength > 0 && textBytes.length > textLength) {
    textBytes = textBytes.sublist(0, textLength);
  }
  final html = decodeBytes(textBytes, codepage: encoding == 65001 ? 0 : 1252);
  final blocks = htmlToBlocks(html);
  if (blocks.isEmpty) {
    throw const BookFormatException('This MOBI contained no readable text.');
  }
  return BookContent(blocks: blocks);
}

String _ascii(Uint8List data, int start, int len) {
  if (start + len > data.length) return '';
  return String.fromCharCodes(data.sublist(start, start + len));
}

/// Strip per-record trailing data entries (whose presence is described by the
/// MOBI "extra data flags") before decompression, so they aren't mistaken for
/// compressed text.
Uint8List _stripTrailing(Uint8List rec, int flags) {
  var end = rec.length;
  var f = flags >> 1;
  while (f != 0) {
    if (f & 1 != 0) {
      end -= _trailerSize(rec, end);
      if (end < 0) return Uint8List(0);
    }
    f >>= 1;
  }
  if (flags & 1 != 0 && end > 0) {
    // Multibyte overlap: low 2 bits of the last byte give the overlap size - 1.
    end -= (rec[end - 1] & 0x3) + 1;
  }
  if (end < 0) end = 0;
  return Uint8List.sublistView(rec, 0, end);
}

/// Size of the trailing data entry ending at [end], read from a backward,
/// 7-bits-per-byte varint in the last (up to) 4 bytes.
int _trailerSize(Uint8List rec, int end) {
  var num = 0;
  for (var i = end - 4; i < end; i++) {
    if (i < 0) continue;
    final v = rec[i];
    if (v & 0x80 != 0) num = 0;
    num = (num << 7) | (v & 0x7f);
  }
  return num;
}

/// Decompress a PalmDOC (LZ77 variant) record.
Uint8List _palmDocDecompress(Uint8List input) {
  final out = <int>[];
  final n = input.length;
  var i = 0;
  while (i < n) {
    final b = input[i++];
    if (b == 0x00) {
      out.add(0x00);
    } else if (b <= 0x08) {
      // Copy the next `b` bytes literally.
      for (var j = 0; j < b && i < n; j++) {
        out.add(input[i++]);
      }
    } else if (b <= 0x7f) {
      out.add(b);
    } else if (b >= 0xc0) {
      // Space + (byte ^ 0x80).
      out.add(0x20);
      out.add(b ^ 0x80);
    } else {
      // 0x80..0xbf: a length/distance pair across this and the next byte.
      if (i >= n) break;
      final b2 = input[i++];
      final pair = (b << 8) | b2;
      final distance = (pair >> 3) & 0x7ff;
      final length = (b2 & 0x07) + 3;
      if (distance == 0) break;
      for (var j = 0; j < length; j++) {
        final idx = out.length - distance;
        out.add(idx < 0 ? 0x20 : out[idx]);
      }
    }
  }
  return Uint8List.fromList(out);
}
