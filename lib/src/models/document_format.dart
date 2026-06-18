/// The kinds of documents the library can hold.
///
/// PDFs are rendered with pdfrx in the fixed-layout [ReaderScreen]; every other
/// (reflowable, text-based) format is read in the flowing `TextReaderScreen`.
enum DocumentFormat {
  pdf,
  epub,
  mobi,
  fb2,
  txt,
  html,
  markdown,
  rtf,
  unknown;

  bool get isPdf => this == DocumentFormat.pdf;

  /// Reflowable, text-based formats read in the flowing text reader.
  bool get isReflowable =>
      this != DocumentFormat.pdf && this != DocumentFormat.unknown;
}

/// The file extensions accepted on import / drag-and-drop (without the dot).
const List<String> kSupportedImportExtensions = <String>[
  'pdf',
  'epub',
  'mobi',
  'azw',
  'azw3',
  'prc',
  'fb2',
  'txt',
  'text',
  'md',
  'markdown',
  'htm',
  'html',
  'xhtml',
  'rtf',
];

/// Determine a document's [DocumentFormat] from its file path/extension.
DocumentFormat documentFormatForPath(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  final ext = (dot < 0 || dot < slash) ? '' : path.substring(dot + 1).toLowerCase();
  switch (ext) {
    case 'pdf':
      return DocumentFormat.pdf;
    case 'epub':
      return DocumentFormat.epub;
    case 'mobi':
    case 'azw':
    case 'azw3':
    case 'prc':
      return DocumentFormat.mobi;
    case 'fb2':
      return DocumentFormat.fb2;
    case 'htm':
    case 'html':
    case 'xhtml':
      return DocumentFormat.html;
    case 'md':
    case 'markdown':
      return DocumentFormat.markdown;
    case 'rtf':
      return DocumentFormat.rtf;
    case 'txt':
    case 'text':
      return DocumentFormat.txt;
    default:
      return DocumentFormat.unknown;
  }
}

/// Whether the file at [path] is an importable document/book format.
bool isSupportedImportPath(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  if (dot < 0 || dot < slash) return false;
  return kSupportedImportExtensions.contains(path.substring(dot + 1).toLowerCase());
}
