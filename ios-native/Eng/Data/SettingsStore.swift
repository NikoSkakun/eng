import Foundation

/// Reads/writes `AppSettings` through `UserDefaults` (the iOS analog of the
/// Flutter app's `shared_preferences`).
struct SettingsStore {
    private let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    private enum Key {
        static let learningLang = "learningLang"
        static let nativeLang = "nativeLang"
        static let translationProvider = "translationProvider"
        static let definitionProvider = "definitionProvider"
        static let myMemoryEmail = "myMemoryEmail"
        static let highlighting = "highlightingEnabled"
        static let autoSuggest = "autoSuggestEnabled"
        static let highlightColor = "highlightColor"
    }

    func load() -> AppSettings {
        var s = AppSettings()
        if let v = defaults.string(forKey: Key.learningLang) { s.learningLang = v }
        if let v = defaults.string(forKey: Key.nativeLang) { s.nativeLang = v }
        if let v = defaults.string(forKey: Key.translationProvider) { s.translationProvider = .from(v) }
        if let v = defaults.string(forKey: Key.definitionProvider) { s.definitionProvider = .from(v) }
        s.myMemoryEmail = defaults.string(forKey: Key.myMemoryEmail) ?? ""
        if defaults.object(forKey: Key.highlighting) != nil { s.highlightingEnabled = defaults.bool(forKey: Key.highlighting) }
        if defaults.object(forKey: Key.autoSuggest) != nil { s.autoSuggestEnabled = defaults.bool(forKey: Key.autoSuggest) }
        if defaults.object(forKey: Key.highlightColor) != nil { s.highlightColor = defaults.integer(forKey: Key.highlightColor) }
        return s
    }

    func save(_ s: AppSettings) {
        defaults.set(s.learningLang, forKey: Key.learningLang)
        defaults.set(s.nativeLang, forKey: Key.nativeLang)
        defaults.set(s.translationProvider.rawValue, forKey: Key.translationProvider)
        defaults.set(s.definitionProvider.rawValue, forKey: Key.definitionProvider)
        defaults.set(s.myMemoryEmail, forKey: Key.myMemoryEmail)
        defaults.set(s.highlightingEnabled, forKey: Key.highlighting)
        defaults.set(s.autoSuggestEnabled, forKey: Key.autoSuggest)
        defaults.set(s.highlightColor, forKey: Key.highlightColor)
    }
}
