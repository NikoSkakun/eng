import Foundation

/// Extract readable text blocks from an XHTML chapter — a lightweight,
/// dependency-free port of the Flutter reader's HTML handling. Structure is kept
/// only at the block level (paragraphs + headings); inline markup, CSS, scripts
/// and images are dropped. Whitespace inside a block is collapsed so source line
/// wrapping doesn't leak into the reader.
enum HtmlText {
    private static let sep = "\u{0001}"    // block separator
    private static let head = "\u{0002}"   // heading marker, followed by a level digit

    static func blocks(from html: String) -> [BookBlock] {
        var s = html

        // 1. Drop XML declaration, doctype, comments, and head/script/style blocks.
        s = replace(s, #"<\?xml[^>]*\?>"#, "")
        s = replace(s, #"<!DOCTYPE[^>]*>"#, "")
        s = replace(s, #"<!--.*?-->"#, "", dotAll: true)
        for tag in ["head", "script", "style"] {
            s = replace(s, "<\(tag)\\b[^>]*>.*?</\(tag)>", "", dotAll: true, caseInsensitive: true)
        }

        // 2. Narrow to <body> if present.
        if let body = firstGroup(s, #"<body\b[^>]*>(.*?)</body>"#, dotAll: true) { s = body }

        // 3. Headings -> SEP + HEAD + level + inner + SEP (inner tags stripped later).
        s = replace(s, #"<h([1-6])\b[^>]*>(.*?)</h[1-6]>"#, "\(sep)\(head)$1$2\(sep)",
                    dotAll: true, caseInsensitive: true)

        // 4. Block-level boundaries (and <br>) become separators.
        let block = "p|div|li|blockquote|br|tr|section|article|hr|figure|figcaption|pre|ul|ol|table|td|th|dd|dt|h[1-6]"
        s = replace(s, "</?(?:\(block))\\b[^>]*/?>", sep, caseInsensitive: true)

        // 5. Strip any remaining tags, then decode entities.
        s = replace(s, "<[^>]+>", "")
        s = decodeEntities(s)

        // 6. Split, collapse whitespace, classify.
        var out: [BookBlock] = []
        for piece in s.components(separatedBy: sep) {
            var text = piece
            var kind = BookBlock.Kind.paragraph
            if text.hasPrefix(head) {
                let after = text.dropFirst()
                let level = after.first.flatMap { $0.wholeNumberValue } ?? 1
                kind = level <= 1 ? .heading1 : (level == 2 ? .heading2 : .heading3)
                text = String(after.dropFirst())
            }
            text = collapseWhitespace(text)
            if text.isEmpty { continue }
            out.append(BookBlock(kind: kind, text: text))
        }
        return out
    }

    /// Strip inline tags, decode entities, collapse whitespace — for short values
    /// like a book title.
    static func plainText(_ s: String) -> String {
        collapseWhitespace(decodeEntities(replace(s, "<[^>]+>", "")))
    }

    // MARK: helpers

    private static func collapseWhitespace(_ s: String) -> String {
        replace(s, #"\s+"#, " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "ldquo": "“", "rdquo": "”", "laquo": "«", "raquo": "»", "copy": "©",
        "reg": "®", "trade": "™", "deg": "°", "middot": "·", "bull": "•",
        "eacute": "é", "egrave": "è", "agrave": "à", "ccedil": "ç", "shy": "",
    ]

    private static func decodeEntities(_ input: String) -> String {
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
                } else {
                    result += ns.substring(with: m.range)
                }
            } else {
                result += namedEntities[body] ?? ns.substring(with: m.range)
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String,
                                dotAll: Bool = false, caseInsensitive: Bool = false) -> String {
        var opts: NSRegularExpression.Options = []
        if dotAll { opts.insert(.dotMatchesLineSeparators) }
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return s }
        let ns = s as NSString
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }

    private static func firstGroup(_ s: String, _ pattern: String, dotAll: Bool = false) -> String? {
        var opts: NSRegularExpression.Options = [.caseInsensitive]
        if dotAll { opts.insert(.dotMatchesLineSeparators) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
