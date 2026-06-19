/// A cached occurrence of a dictionary term inside one document: a display-ready
/// [snippet] (a whole paragraph for reflowable books, or a windowed snippet for
/// a PDF page) plus a pointer back to the source so the reader can jump there.
///
/// The pointer is [page] for PDFs (1-based) and [blockIndex] for reflowable
/// books (the index of the paragraph block in the flowing reader).
class Usage {
  Usage({
    required this.id,
    required this.entryId,
    required this.documentId,
    this.page,
    this.blockIndex,
    required this.snippet,
    required this.highlights,
  });

  final int id;
  final int entryId;
  final int documentId;

  /// Jump target for PDFs (1-based page), null for reflowable books.
  final int? page;

  /// Jump target for reflowable books (paragraph block index), null for PDFs.
  final int? blockIndex;

  final String snippet;

  /// Ranges within [snippet] (code-unit `[start, end)`) to emphasize.
  final List<({int start, int end})> highlights;
}
