/// A user-created folder for grouping library documents.
///
/// Folders nest arbitrarily: [parentId] is the containing folder, or null for a
/// folder at the library root. [position] orders the folder among the items of
/// its parent.
class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.parentId,
    this.position = 0,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final int? parentId;
  final int position;

  LibraryFolder copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    Object? parentId = _sentinel,
    int? position,
  }) {
    return LibraryFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId == _sentinel ? this.parentId : parentId as int?,
      position: position ?? this.position,
    );
  }

  static const Object _sentinel = Object();
}
