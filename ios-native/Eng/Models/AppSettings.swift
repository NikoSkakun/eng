import SwiftUI
import UIKit

/// Identifiers for the available translation providers (keyless set for v1).
enum TranslationProviderId: String, CaseIterable, Identifiable {
    case myMemory = "mymemory"
    case googleUnofficial = "google"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .myMemory: return "MyMemory (free, no key)"
        case .googleUnofficial: return "Google (unofficial, no key)"
        }
    }

    static func from(_ id: String) -> TranslationProviderId { TranslationProviderId(rawValue: id) ?? .myMemory }
}

/// Identifiers for the available definition providers.
enum DefinitionProviderId: String, CaseIterable, Identifiable {
    case dictionaryApi = "dictionaryapi"
    case wiktionary = "wiktionary"
    case none = "none"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dictionaryApi: return "Free Dictionary API (English)"
        case .wiktionary: return "Wiktionary"
        case .none: return "None"
        }
    }

    static func from(_ id: String) -> DefinitionProviderId { DefinitionProviderId(rawValue: id) ?? .dictionaryApi }
}

/// Default highlight color (semi-transparent amber), as 32-bit ARGB.
let kDefaultHighlightColor = 0x66FFC107

/// A language the app can translate to/from.
struct AppLanguage: Identifiable, Hashable {
    let code: String        // ISO 639-1, lower-case
    let englishName: String
    let nativeName: String
    var id: String { code }
}

let kSupportedLanguages: [AppLanguage] = [
    .init(code: "en", englishName: "English", nativeName: "English"),
    .init(code: "uk", englishName: "Ukrainian", nativeName: "Українська"),
    .init(code: "de", englishName: "German", nativeName: "Deutsch"),
    .init(code: "fr", englishName: "French", nativeName: "Français"),
    .init(code: "es", englishName: "Spanish", nativeName: "Español"),
    .init(code: "it", englishName: "Italian", nativeName: "Italiano"),
    .init(code: "pl", englishName: "Polish", nativeName: "Polski"),
    .init(code: "pt", englishName: "Portuguese", nativeName: "Português"),
    .init(code: "ru", englishName: "Russian", nativeName: "Русский"),
    .init(code: "nl", englishName: "Dutch", nativeName: "Nederlands"),
    .init(code: "cs", englishName: "Czech", nativeName: "Čeština"),
    .init(code: "tr", englishName: "Turkish", nativeName: "Türkçe"),
]

/// Languages for which the bundled definition providers return definitions.
let kDefinitionLanguages: Set<String> = ["en"]

func languageForCode(_ code: String) -> AppLanguage {
    kSupportedLanguages.first { $0.code == code }
        ?? AppLanguage(code: code, englishName: code.uppercased(), nativeName: code.uppercased())
}

let kDefaultLearningLang = "en"   // language of the documents being read
let kDefaultNativeLang = "uk"     // the reader's own language

/// Immutable snapshot of all user settings.
struct AppSettings: Equatable {
    var learningLang = kDefaultLearningLang
    var nativeLang = kDefaultNativeLang
    var translationProvider: TranslationProviderId = .myMemory
    var definitionProvider: DefinitionProviderId = .dictionaryApi
    /// Optional email to raise MyMemory's anonymous quota (5k -> 50k chars/day).
    var myMemoryEmail = ""
    var highlightingEnabled = true
    var autoSuggestEnabled = true
    /// 32-bit ARGB color used for highlights without a per-entry color.
    var highlightColor = kDefaultHighlightColor

    // Reflowable (EPUB) reader appearance — see `ReaderStyle.swift`.
    var readerFont: ReaderFont = .serif
    var readerFontSize: Double = kDefaultReaderFontSize
    /// Extra points between lines (NSParagraphStyle.lineSpacing).
    var readerLineSpacing: Double = 7
    var readerTheme: ReaderTheme = .system
    var readerMargin: ReaderMargin = .medium
    var readerJustified: Bool = false

    /// Whether definitions can be looked up given the current learning language.
    var definitionsAvailable: Bool {
        definitionProvider != .none && kDefinitionLanguages.contains(learningLang)
    }
}

/// ARGB <-> SwiftUI/UIKit color helpers (matches the Flutter app's 0xAARRGGBB).
extension Color {
    init(argb: Int) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension UIColor {
    convenience init(argb: Int) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
