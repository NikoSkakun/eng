import Foundation

/// Wiktionary REST definition endpoint — keyless fallback for definitions.
/// `GET https://<lang>.wiktionary.org/api/rest_v1/page/definition/<word>`
/// Returns an object keyed by language code; definitions are HTML and sanitized.
struct WiktionaryProvider: DefinitionProvider {
    var id: String { "wiktionary" }
    private static let userAgent = "eng-reader-ios/1.0 (language-learning reader; contact: in-app)"

    func define(word: String, lang: String) async throws -> DefinitionResult {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        guard let url = URL(string: "https://\(lang).wiktionary.org/api/rest_v1/page/definition/\(encoded)") else {
            throw ProviderError("Bad word", notFound: true)
        }
        let (data, resp): (Data, HTTPURLResponse)
        do { (data, resp) = try await Http.get(url, headers: ["User-Agent": Self.userAgent, "Accept": "application/json"]) }
        catch { throw ProviderError("Network error contacting Wiktionary: \(error.localizedDescription)") }
        if resp.statusCode == 404 { throw ProviderError("No Wiktionary entry for \"\(word)\".", notFound: true) }
        guard resp.statusCode == 200 else { throw ProviderError("Wiktionary returned HTTP \(resp.statusCode)") }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError("No Wiktionary entry for \"\(word)\".", notFound: true)
        }
        // Prefer definitions in the requested language; fall back to any present.
        let entries = (obj[lang] as? [[String: Any]]) ?? (obj.values.first { $0 is [[String: Any]] } as? [[String: Any]])
        guard let entries, !entries.isEmpty else {
            throw ProviderError("No Wiktionary entry for \"\(word)\".", notFound: true)
        }

        var senses: [DefinitionSense] = []
        for e in entries {
            let pos = (e["partOfSpeech"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            var items: [DefinitionItem] = []
            if let defs = e["definitions"] as? [[String: Any]] {
                for d in defs {
                    let def = Self.stripHtml((d["definition"] as? String) ?? "")
                    if def.isEmpty { continue }
                    var example: String?
                    if let examples = d["examples"] as? [Any], let first = examples.first {
                        example = Self.stripHtml("\(first)")
                    }
                    items.append(DefinitionItem(definition: def, example: example))
                }
            }
            if !items.isEmpty { senses.append(DefinitionSense(partOfSpeech: pos, items: items)) }
        }
        if senses.isEmpty { throw ProviderError("No Wiktionary entry for \"\(word)\".", notFound: true) }
        return DefinitionResult(word: word, senses: senses, providerId: id,
                                attribution: "Definitions: Wiktionary (CC BY-SA)")
    }

    private static let tagPattern = try! NSRegularExpression(pattern: "<[^>]*>")

    /// Strip HTML tags and decode the handful of entities Wiktionary emits.
    static func stripHtml(_ html: String) -> String {
        let ns = html as NSString
        var text = tagPattern.stringByReplacingMatches(
            in: html, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&nbsp;": " "]
        for (k, v) in entities { text = text.replacingOccurrences(of: k, with: v) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
