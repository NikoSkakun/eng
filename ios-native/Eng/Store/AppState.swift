import Foundation
import SwiftUI

/// The app's single source of truth (the iOS analog of the Flutter app's Riverpod
/// controllers). Holds the settings, the whole dictionary, and the library; all
/// mutations go through here so views observing it refresh and the reader rebuilds
/// its matcher.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var entries: [DictionaryEntry] = []
    @Published private(set) var documents: [LibraryDocument] = []
    /// Increments on every dictionary or settings change — the reader watches this
    /// to know when to rebuild its `TermMatcher`.
    @Published private(set) var dictionaryRevision = 0

    private let db: Database
    private let dict: DictionaryRepository
    private let library: LibraryRepository
    private let cache: CacheRepository
    private let settingsStore = SettingsStore()

    init() {
        // Fatal here is acceptable: without a database there is no app.
        do { db = try Database(url: AppPaths.databaseURL) }
        catch { fatalError("Cannot open database: \(error)") }
        dict = DictionaryRepository(db: db)
        library = LibraryRepository(db: db)
        cache = CacheRepository(db: db)
        settings = settingsStore.load()
        reloadEntries()
        reloadDocuments()
    }

    var translationService: TranslationService { TranslationService(settings: settings, cache: cache) }

    // MARK: Dictionary

    func reloadEntries() { entries = (try? dict.fetchAll()) ?? [] }

    func entry(id: Int64) -> DictionaryEntry? { entries.first { $0.id == id } }

    /// An existing global (or same-document) entry whose normalized key matches
    /// `term` — so selecting a word already in the dictionary edits it rather than
    /// creating a duplicate.
    func existingEntry(forTerm term: String, documentId: Int64?) -> DictionaryEntry? {
        let key = TextNormalizer.normalizeKey(term)
        return entries.first {
            $0.normalizedTerm == key && ($0.scopeDocumentId == nil || $0.scopeDocumentId == documentId)
        }
    }

    /// Terms eligible to highlight in a given document: highlight-enabled, in the
    /// learning language, and either global or scoped to this document.
    func matchableTerms(documentId: Int64?) -> [MatchableTerm] {
        entries.compactMap { e in
            guard e.highlightEnabled, e.sourceLang == settings.learningLang else { return nil }
            if let scope = e.scopeDocumentId, scope != documentId { return nil }
            return MatchableTerm.fromTerm(e.id, e.term, partial: e.matchPartial)
        }
    }

    func matcher(documentId: Int64?) -> TermMatcher {
        TermMatcher(settings.highlightingEnabled ? matchableTerms(documentId: documentId) : [])
    }

    @discardableResult
    func addEntry(_ entry: DictionaryEntry) -> Int64? {
        do {
            let id = try dict.insert(entry)
            reloadEntries(); bump()
            return id
        } catch { return nil }
    }

    func updateEntry(_ entry: DictionaryEntry) {
        try? dict.update(entry); reloadEntries(); bump()
    }

    func deleteEntry(_ id: Int64) {
        try? dict.delete(id); reloadEntries(); bump()
    }

    func toggleHighlight(_ entry: DictionaryEntry) {
        var e = entry; e.highlightEnabled.toggle(); updateEntry(e)
    }

    private func bump() { dictionaryRevision &+= 1 }

    // MARK: Library

    func reloadDocuments() { documents = (try? library.fetchAll()) ?? [] }

    /// Copy a picked PDF into the managed library and register it.
    @discardableResult
    func importDocument(from source: URL) throws -> LibraryDocument {
        let needsStop = source.startAccessingSecurityScopedResource()
        defer { if needsStop { source.stopAccessingSecurityScopedResource() } }

        let baseName = source.deletingPathExtension().lastPathComponent
        let dest = uniqueDestination(for: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: dest)

        let pageCount = PDFDocumentInfo.pageCount(at: dest)
        var doc = LibraryDocument(id: 0, title: baseName, fileName: dest.lastPathComponent,
                                  originalPath: source.path, pageCount: pageCount,
                                  addedAt: Date(), lastOpenedAt: nil, lastPage: 1)
        doc.id = try library.insert(doc)
        reloadDocuments()
        return doc
    }

    func deleteDocument(_ doc: LibraryDocument) {
        try? FileManager.default.removeItem(at: doc.fileURL)
        try? library.delete(doc.id)     // cascade drops document-scoped entries
        reloadDocuments(); reloadEntries()
    }

    func renameDocument(_ doc: LibraryDocument, to title: String) {
        try? library.rename(id: doc.id, title: title); reloadDocuments()
    }

    func saveProgress(documentId: Int64, page: Int, viewState: DocumentViewState?) {
        try? library.updateProgress(id: documentId, lastPage: page, viewState: viewState)
        if let i = documents.firstIndex(where: { $0.id == documentId }) {
            documents[i].lastPage = page
            documents[i].lastOpenedAt = Date()
            documents[i].viewState = viewState
        }
    }

    private func uniqueDestination(for fileName: String) -> URL {
        let dir = AppPaths.libraryDirectory
        var candidate = dir.appendingPathComponent(fileName)
        let ext = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: Settings

    func updateSettings(_ newValue: AppSettings) {
        settings = newValue
        settingsStore.save(newValue)
        bump()   // language/provider/highlighting changes affect matching + lookups
    }

    func mutateSettings(_ transform: (inout AppSettings) -> Void) {
        var s = settings; transform(&s); updateSettings(s)
    }
}
