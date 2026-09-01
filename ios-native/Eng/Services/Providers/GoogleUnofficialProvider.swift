import Foundation

/// Unofficial Google Translate endpoint (`translate_a/single`). Keyless and high
/// quality, but undocumented and unsupported by Google — opt-in only, never the
/// default.
struct GoogleUnofficialProvider: TranslationProvider {
    var id: String { "google" }

    func translate(text: String, from: String, to: String) async throws -> TranslationResult {
        var comps = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: from),
            URLQueryItem(name: "tl", value: to),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        let (data, resp): (Data, HTTPURLResponse)
        do { (data, resp) = try await Http.get(comps.url!) }
        catch { throw ProviderError("Network error contacting Google: \(error.localizedDescription)") }
        guard resp.statusCode == 200 else { throw ProviderError("Google endpoint returned HTTP \(resp.statusCode)") }

        // Response shape: [ [ [translatedChunk, sourceChunk, ...], ... ], ... ]
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            throw ProviderError("Unexpected response from Google endpoint.")
        }
        var buffer = ""
        for seg in segments {
            if let arr = seg as? [Any], let chunk = arr.first as? String { buffer += chunk }
        }
        let translated = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if translated.isEmpty { throw ProviderError("Google endpoint returned no translation.") }
        return TranslationResult(translatedText: translated, providerId: id, attribution: "Translation by Google")
    }
}
