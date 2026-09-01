import Foundation

/// MyMemory translation API — keyless, supports en<->uk and many pairs.
/// `GET https://api.mymemory.translated.net/get?q=..&langpair=en|uk&de=email`
/// An email (optional) raises the anonymous quota from 5k to 50k chars/day.
struct MyMemoryProvider: TranslationProvider {
    let email: String
    var id: String { "mymemory" }

    func translate(text: String, from: String, to: String) async throws -> TranslationResult {
        var comps = URLComponents(string: "https://api.mymemory.translated.net/get")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: "\(from)|\(to)"),
        ]
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty { comps.queryItems!.append(URLQueryItem(name: "de", value: trimmedEmail)) }

        let (data, resp): (Data, HTTPURLResponse)
        do { (data, resp) = try await Http.get(comps.url!) }
        catch { throw ProviderError("Network error contacting MyMemory: \(error.localizedDescription)") }
        guard resp.statusCode == 200 else { throw ProviderError("MyMemory returned HTTP \(resp.statusCode)") }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError("MyMemory: bad response")
        }
        let status = json["responseStatus"]
        let statusOk = (status as? Int == 200) || (status as? String == "200")
        let responseData = json["responseData"] as? [String: Any]
        let primary = (responseData?["translatedText"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !statusOk || primary.isEmpty {
            let detail = (json["responseDetails"] as? String) ?? "no translation"
            throw ProviderError("MyMemory: \(detail)")
        }

        var alternatives: [String] = []
        if let matches = json["matches"] as? [[String: Any]] {
            for m in matches {
                if let t = (m["translation"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !t.isEmpty, t.lowercased() != primary.lowercased(), !alternatives.contains(t) {
                    alternatives.append(t)
                }
            }
        }
        return TranslationResult(translatedText: primary,
                                 alternatives: Array(alternatives.prefix(6)),
                                 providerId: id,
                                 attribution: "Translation by MyMemory")
    }
}
