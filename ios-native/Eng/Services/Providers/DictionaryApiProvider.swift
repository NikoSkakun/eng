import Foundation

/// Free Dictionary API (dictionaryapi.dev) — keyless English definitions.
/// `GET https://api.dictionaryapi.dev/api/v2/entries/en/<word>` (404 = no entry).
/// Data is sourced from Wiktionary under CC BY-SA.
struct DictionaryApiProvider: DefinitionProvider {
    var id: String { "dictionaryapi" }

    func define(word: String, lang: String) async throws -> DefinitionResult {
        let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        guard let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/\(lang)/\(encoded)") else {
            throw ProviderError("Bad word", notFound: true)
        }
        let (data, resp): (Data, HTTPURLResponse)
        do { (data, resp) = try await Http.get(url) }
        catch { throw ProviderError("Network error contacting the dictionary: \(error.localizedDescription)") }
        if resp.statusCode == 404 { throw ProviderError("No definition found for \"\(word)\".", notFound: true) }
        guard resp.statusCode == 200 else { throw ProviderError("Dictionary API returned HTTP \(resp.statusCode)") }

        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !arr.isEmpty else {
            throw ProviderError("No definition found for \"\(word)\".", notFound: true)
        }

        var phonetic: String?
        var audioUrl: String?
        var senses: [DefinitionSense] = []

        for entry in arr {
            if phonetic == nil { phonetic = (entry["phonetic"] as? String)?.trimmingCharacters(in: .whitespaces) }
            if let phonetics = entry["phonetics"] as? [[String: Any]] {
                for p in phonetics {
                    if phonetic == nil || phonetic!.isEmpty { phonetic = (p["text"] as? String)?.trimmingCharacters(in: .whitespaces) }
                    if audioUrl == nil, let a = (p["audio"] as? String)?.trimmingCharacters(in: .whitespaces), !a.isEmpty { audioUrl = a }
                }
            }
            if let meanings = entry["meanings"] as? [[String: Any]] {
                for m in meanings {
                    let pos = (m["partOfSpeech"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                    var items: [DefinitionItem] = []
                    if let defs = m["definitions"] as? [[String: Any]] {
                        for d in defs {
                            guard let def = (d["definition"] as? String)?.trimmingCharacters(in: .whitespaces), !def.isEmpty else { continue }
                            items.append(DefinitionItem(definition: def,
                                                        example: (d["example"] as? String)?.trimmingCharacters(in: .whitespaces)))
                        }
                    }
                    if !items.isEmpty { senses.append(DefinitionSense(partOfSpeech: pos, items: items)) }
                }
            }
        }
        if senses.isEmpty { throw ProviderError("No definition found for \"\(word)\".", notFound: true) }

        return DefinitionResult(word: word,
                                phonetic: (phonetic?.isEmpty ?? true) ? nil : phonetic,
                                senses: senses,
                                providerId: id,
                                attribution: "Definitions: Wiktionary (CC BY-SA) via dictionaryapi.dev",
                                audioUrl: audioUrl)
    }
}
