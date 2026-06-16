/// A user-created folder for grouping library documents.
///
/// Folders are flat (a document belongs to at most one folder); a document with
/// a null `folderId` lives at the library root.
class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final int id;
  final String name;
  final DateTime createdAt;

  LibraryFolder copyWith({int? id, String? name, DateTime? createdAt}) {
    return LibraryFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
