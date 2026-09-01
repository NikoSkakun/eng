import Foundation

/// A user's dictionary entry: a term (word or phrase) the reader is learning,
/// together with its translation and/or definition.
///
/// Entries are *shared* by default: when `scopeDocumentId` is nil the term is
/// highlighted across every document in the library. Setting it to a document id
/// scopes the highlight (and lookup) to that single document.
struct DictionaryEntry: Identifiable, Equatable {
    /// Row id (`0` for an entry not yet persisted).
    var id: Int64
    /// Original surface form of the term as entered or selected.
    var term: String
    /// Language of `term` (the learning language), ISO 639-1.
    var sourceLang: String
    /// Language of `translation` (the native language), ISO 639-1.
    var targetLang: String
    /// User-confirmed (or suggested-then-kept) primary translation.
    var translation: String?
    /// Additional accepted translations, shown alongside the primary one. Never
    /// nil (empty when there are none); order is the user's.
    var alternativeTranslations: [String] = []
    /// User definition or a looked-up monolingual definition.
    var definition: String?
    /// Free-form notes.
    var notes: String?
    /// Whether this term participates in auto-highlighting.
    var highlightEnabled: Bool = true
    /// Optional per-entry highlight color as a 32-bit ARGB value; nil = app default.
    var colorValue: Int?
    /// When true, a single-word term also matches as a *part* of longer words at
    /// sub-word boundaries. Only meaningful for single-word terms.
    var matchPartial: Bool = false
    /// The word the term was originally selected from, when created from a partial
    /// in-word selection. Informational.
    var sourceWord: String?
    /// When set, the entry only applies to the document with this id.
    var scopeDocumentId: Int64?
    var createdAt: Date
    var updatedAt: Date

    /// Canonical key used for matching and de-duplication (derived from `term`).
    var normalizedTerm: String { TextNormalizer.normalizeKey(term) }

    var isGlobal: Bool { scopeDocumentId == nil }

    /// Every translation to display, primary first, trimmed and de-duplicated
    /// case-insensitively (empties removed). Falls back to the alternatives when
    /// no primary is set.
    var allTranslations: [String] {
        var out: [String] = []
        var seen = Set<String>()
        for t in ([translation].compactMap { $0 } + alternativeTranslations) {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            if seen.insert(s.lowercased()).inserted { out.append(s) }
        }
        return out
    }

    /// Whether the term carries more than one translation variant.
    var hasMultipleTranslations: Bool { allTranslations.count > 1 }

    /// The single translation to render inline (interlinear gloss): the primary.
    var glossText: String? { allTranslations.first }

    var hasContent: Bool {
        !allTranslations.isEmpty || !(definition?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    static func == (a: DictionaryEntry, b: DictionaryEntry) -> Bool { a.id == b.id && a.updatedAt == b.updatedAt }
}
