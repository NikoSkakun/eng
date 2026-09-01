import Foundation

/// The kinds of document the reader can open. PDFs render fixed-layout via
/// PDFKit; EPUBs are reflowable text.
enum DocumentFormat {
    case pdf
    case epub

    static func forExtension(_ ext: String) -> DocumentFormat? {
        switch ext.lowercased() {
        case "pdf": return .pdf
        case "epub": return .epub
        default: return nil
        }
    }

    static func forPath(_ url: URL) -> DocumentFormat? {
        forExtension(url.pathExtension)
    }

    var isReflowable: Bool { self == .epub }
}

/// File extensions the library import accepts.
let kSupportedImportExtensions: Set<String> = ["pdf", "epub"]

extension LibraryDocument {
    /// Derived from the file name so no schema column is needed.
    var format: DocumentFormat { DocumentFormat.forExtension((fileName as NSString).pathExtension) ?? .pdf }
}
