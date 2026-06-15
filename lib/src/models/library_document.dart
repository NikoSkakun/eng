/// A PDF stored in the app's library.
///
/// The file itself is copied into the app's documents directory on import so
/// the library is self-contained (and keeps working if the original file is
/// moved or deleted).
class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.title,
    required this.filePath,
    this.originalPath,
    this.pageCount = 0,
    required this.addedAt,
    this.lastOpenedAt,
    this.lastPage = 1,
    this.viewMatrix,
  });

  final int id;

  /// Display title (defaults to the file name without extension).
  final String title;

  /// Absolute path to the managed copy inside the app library directory.
  final String filePath;

  /// Where the file was imported from, for reference.
  final String? originalPath;

  /// Number of pages, or 0 if not yet determined.
  final int pageCount;

  final DateTime addedAt;
  final DateTime? lastOpenedAt;

  /// 1-based page the reader was last on (reading position).
  final int lastPage;

  /// Serialized pdfrx view matrix (16 comma-separated doubles) capturing the
  /// exact scroll position and zoom; null until the document has been viewed.
  final String? viewMatrix;

  LibraryDocument copyWith({
    int? id,
    String? title,
    String? filePath,
    Object? originalPath = _sentinel,
    int? pageCount,
    DateTime? addedAt,
    Object? lastOpenedAt = _sentinel,
    int? lastPage,
    Object? viewMatrix = _sentinel,
  }) {
    return LibraryDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      originalPath: originalPath == _sentinel
          ? this.originalPath
          : originalPath as String?,
      pageCount: pageCount ?? this.pageCount,
      addedAt: addedAt ?? this.addedAt,
      lastOpenedAt: lastOpenedAt == _sentinel
          ? this.lastOpenedAt
          : lastOpenedAt as DateTime?,
      lastPage: lastPage ?? this.lastPage,
      viewMatrix: viewMatrix == _sentinel
          ? this.viewMatrix
          : viewMatrix as String?,
    );
  }

  static const Object _sentinel = Object();
}
