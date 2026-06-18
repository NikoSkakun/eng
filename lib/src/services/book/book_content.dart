/// Parsed, reflowable representation of a text-based book/document.
///
/// A book is reduced to an ordered list of [BookBlock]s (paragraphs and
/// headings). This is deliberately format-agnostic: every parser (EPUB, MOBI,
/// FB2, TXT, HTML, Markdown, RTF) produces the same shape, so the text reader
/// needs to understand only [BookContent].
class BookContent {
  const BookContent({required this.blocks, this.title});

  /// The document's blocks in reading order.
  final List<BookBlock> blocks;

  /// Title parsed from the document's metadata, if any.
  final String? title;

  /// Total number of characters across all blocks (used to estimate a page
  /// count for the library and to position the reader within the document).
  int get totalChars {
    var n = 0;
    for (final b in blocks) {
      n += b.text.length;
    }
    return n;
  }
}

/// A single flowing block of text: a paragraph or a heading.
class BookBlock {
  const BookBlock(this.text, {this.heading = false});

  /// The block's plain text (whitespace already collapsed; never empty).
  final String text;

  /// Whether the block is a heading (rendered larger/bold).
  final bool heading;
}

/// Thrown when a file cannot be parsed into readable text. The [message] is
/// safe to show to the user.
class BookFormatException implements Exception {
  const BookFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}
