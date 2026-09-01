import Foundation

/// A PDF imported into the app-managed library. The file itself is a copy kept
/// under the app's Documents/library folder; `fileName` is its name there.
struct LibraryDocument: Identifiable, Equatable {
    var id: Int64
    var title: String
    /// File name inside the managed `library/` directory (not an absolute path,
    /// so it survives the container path changing between installs).
    var fileName: String
    /// The path the file was imported from, for reference/display.
    var originalPath: String?
    var pageCount: Int
    var addedAt: Date
    var lastOpenedAt: Date?
    /// 1-based page the reader should resume on (fallback when `viewState` is absent).
    var lastPage: Int = 1
    /// Exact reading position + zoom, restored verbatim on the next open.
    var viewState: DocumentViewState? = nil

    /// Absolute URL of the managed copy, resolved against the current container.
    var fileURL: URL { AppPaths.libraryDirectory.appendingPathComponent(fileName) }
}

/// The reader's exact view of a document: the current page, the top-left point of
/// the visible area in PDF page space (what `PDFView.currentDestination` reports),
/// and the absolute zoom (`scaleFactor`). Serialized as JSON into the documents
/// table's `view_matrix` column (the same column the Flutter app uses).
struct DocumentViewState: Codable, Equatable {
    /// Format version. v2 = point computed via `convert(_:to:)` (true page space).
    /// The key is REQUIRED when decoding, so states saved by the first build —
    /// whose `currentDestination`-derived points restored about a page off — fail
    /// to decode and fall back to the plain last-page resume.
    var v: Int = 2
    /// 0-based page index.
    var pageIndex: Int
    /// Top-left of the visible area, in page space (origin bottom-left).
    var x: Double
    var y: Double
    /// `PDFView.scaleFactor` at the time of saving.
    var zoom: Double

    var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func from(json: String?) -> DocumentViewState? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(DocumentViewState.self, from: Data(json.utf8))
    }
}

/// Resolves the app's on-disk locations. Everything lives under the app-support
/// dir: the SQLite database plus a `library/` folder holding copies of imports.
enum AppPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var libraryDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("library", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var databaseURL: URL { supportDirectory.appendingPathComponent("eng.db") }
}
