import Foundation

/// Small shared HTML helpers: entity decoding and a plain-text flattener (used
/// for short values like the book title). Block/inline extraction lives in
/// `HtmlParser`.
enum HtmlText {
    /// Strip inline tags, decode entities, collapse whitespace — for short values.
    static func plainText(_ s: String) -> String {
        let noTags = replace(s, "<[^>]+>", "")
        return collapseWhitespace(decodeEntities(noTags))
    }

    static func collapseWhitespace(_ s: String) -> String {
        replace(s, #"\s+"#, " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»", "copy": "©",
        "reg": "®", "trade": "™", "deg": "°", "middot": "·", "bull": "•",
        "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç", "shy": "",
    ]

    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        let re = try! NSRegularExpression(pattern: "&(#x?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);")
        let ns = input as NSString
        var result = ""
        var last = 0
        re.enumerateMatches(in: input, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            if body.hasPrefix("#") {
                let hex = body.hasPrefix("#x") || body.hasPrefix("#X")
                let digits = String(body.dropFirst(hex ? 2 : 1))
                if let code = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    result += String(scalar)
                } else { result += ns.substring(with: m.range) }
            } else {
                result += namedEntities[body] ?? ns.substring(with: m.range)
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    static func replace(_ s: String, _ pattern: String, _ template: String,
                        dotAll: Bool = false, caseInsensitive: Bool = false) -> String {
        var opts: NSRegularExpression.Options = []
        if dotAll { opts.insert(.dotMatchesLineSeparators) }
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}
