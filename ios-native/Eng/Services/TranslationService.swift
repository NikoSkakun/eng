import Foundation

protocol TranslationProvider {
    var id: String { get }
    func translate(text: String, from: String, to: String) async throws -> TranslationResult
}

protocol DefinitionProvider {
    var id: String { get }
    func define(word: String, lang: String) async throws -> DefinitionResult
}

/// Orchestrates translation and definition providers based on `AppSettings`, with
/// a keyless fallback and an on-disk cache — a port of the Flutter
/// `TranslationService`. A fresh instance is created whenever settings change, so
/// it always reflects the current provider/keys.
struct TranslationService {
    let settings: AppSettings
    let cache: CacheRepository

    /// How long a "no definition found" result is cached before re-checking.
    private static let negativeDefinitionTtlMs = 24 * 60 * 60 * 1000  // 1 day

    private func buildTranslationProvider(_ id: TranslationProviderId) -> TranslationProvider {
        switch id {
        case .myMemory: return MyMemoryProvider(email: settings.myMemoryEmail)
        case .googleUnofficial: return GoogleUnofficialProvider()
        }
    }

    private func primaryDefinitionProvider() -> DefinitionProvider? {
        switch settings.definitionProvider {
        case .dictionaryApi: return DictionaryApiProvider()
        case .wiktionary: return WiktionaryProvider()
        case .none: return nil
        }
    }

    /// Translate `text`. Tries the configured provider, then keyless MyMemory as a
    /// fallback, and caches the result. Throws only if every attempt fails.
    func suggestTranslation(_ text: String, from: String? = nil, to: String? = nil) async throws -> TranslationResult {
        let src = from ?? settings.learningLang
        let dst = to ?? settings.nativeLang
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "tr:\(settings.translationProvider.id):\(src)>\(dst):\(trimmed.lowercased())"
        if let cached: TranslationResult = readCache(cacheKey) { return cached }

        var attempts: [TranslationProvider] = [buildTranslationProvider(settings.translationProvider)]
        if settings.translationProvider != .myMemory {
            attempts.append(MyMemoryProvider(email: settings.myMemoryEmail))
        }

        var lastError: Error?
        for provider in attempts {
            do {
                let result = try await provider.translate(text: trimmed, from: src, to: dst)
                writeCache(cacheKey, result)
                return result
            } catch { lastError = error }
        }
        throw lastError ?? ProviderError("Translation failed.")
    }

    /// Look up a definition for `word`. Returns nil if no provider finds one (or
    /// definitions are disabled). Throws only on a hard failure that isn't "not found".
    func lookupDefinition(_ word: String, lang: String? = nil) async throws -> DefinitionResult? {
        let language = lang ?? settings.learningLang
        guard let primary = primaryDefinitionProvider() else { return nil }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "def:\(primary.id):\(language):\(trimmed.lowercased())"
        if let raw = cache.get(cacheKey), let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
            if obj["_empty"] as? Bool == true {
                let exp = obj["_exp"] as? Int ?? 0
                if nowMs() < exp { return nil }   // fresh negative entry
                // else fall through and re-fetch
            } else if let result: DefinitionResult = decode(raw) {
                return result
            }
        }

        var attempts: [DefinitionProvider] = [primary]
        if primary.id != "wiktionary" { attempts.append(WiktionaryProvider()) }

        var hardError: Error?
        for provider in attempts {
            do {
                let result = try await provider.define(word: trimmed, lang: language)
                writeCache(cacheKey, result)
                return result
            } catch let e as ProviderError {
                if !e.notFound { hardError = e }
            } catch { hardError = error }
        }
        if let hardError { throw hardError }
        // Every provider returned "not found": cache the negative result with a TTL.
        let neg = ["_empty": true, "_exp": nowMs() + Self.negativeDefinitionTtlMs] as [String: Any]
        if let data = try? JSONSerialization.data(withJSONObject: neg) {
            cache.put(cacheKey, String(decoding: data, as: UTF8.self))
        }
        return nil
    }

    private func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    private func readCache<T: Decodable>(_ key: String) -> T? {
        guard let raw = cache.get(key) else { return nil }
        return decode(raw)
    }
    private func decode<T: Decodable>(_ raw: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(raw.utf8))
    }
    private func writeCache<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) {
            cache.put(key, String(decoding: data, as: UTF8.self))
        }
    }
}

/// Shared helpers for the providers.
enum Http {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    static func get(_ url: URL, headers: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError("No HTTP response") }
        return (data, http)
    }
}
