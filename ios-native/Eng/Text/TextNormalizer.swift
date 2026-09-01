import Foundation

/// A single word token and its half-open source range `[start, end)` in **UTF-16
/// code-unit** offsets — the same unit PDFKit's `NSRange`/`characterBounds(at:)`
/// use, so a match range can be handed straight to `PDFPage`.
struct Token {
    let start: Int
    let end: Int
    let text: String
}

/// Text normalization shared by the matching engine and dictionary storage —
/// a direct port of the Flutter app's `TextNormalizer`.
///
/// Two distinct needs are served here:
///  * `normalizeKey` produces a canonical, length-*insensitive* key used to
///    compare/deduplicate terms (may collapse whitespace, fold case).
///  * `normalizeToken` normalizes a single isolated word **1:1 per code unit**
///    (only case-fold + unify a few punctuation variants), so match offsets
///    computed against a normalized token still index into the raw page text
///    and its per-character rectangles.
enum TextNormalizer {
    /// Characters treated as equivalent to a straight apostrophe.
    private static let apostrophes = Set("'’ʼ‘`´".unicodeScalars)
    /// Characters treated as equivalent to an ASCII hyphen-minus.
    private static let hyphens = Set("-‐‑‒–—−".unicodeScalars)

    /// Normalize a single token (a "word"): lower-case and unify apostrophe and
    /// hyphen variants. Length is preserved for the scripts the app targets, so
    /// callers may keep using the token's original source offsets.
    static func normalizeToken(_ token: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(token.unicodeScalars.count)
        for scalar in token.unicodeScalars {
            if apostrophes.contains(scalar) {
                out.append("'")
            } else if hyphens.contains(scalar) {
                out.append("-")
            } else {
                // Lower-case per scalar (1:1 for the Latin text we target).
                out.append(contentsOf: String(scalar).lowercased().unicodeScalars)
            }
        }
        return String(out)
    }

    /// Normalize an arbitrary string into a canonical lookup/dedup key: unify
    /// punctuation, lower-case, and collapse internal whitespace to single spaces.
    static func normalizeKey(_ input: String) -> String {
        tokenize(input).map { normalizeToken($0.text) }.joined(separator: " ")
    }

    // The connector characters allowed inside a word, as a regex character-class
    // body. The ASCII hyphen is escaped so it isn't read as a range operator.
    private static let wordConnectors = #"'’ʼ‘`´\-‐‑‒–—−"#

    private static let tokenRegex: NSRegularExpression = {
        let pattern = "[\\p{L}\\p{N}]+(?:[\(wordConnectors)][\\p{L}\\p{N}]+)*"
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Split `input` into word tokens with their UTF-16 source offsets.
    ///
    /// A token is a maximal run of Unicode letters/digits, optionally joined by a
    /// single apostrophe or hyphen between two such runs (so `don't`,
    /// `well-known` and `café` are single tokens).
    static func tokenize(_ input: String) -> [Token] {
        let ns = input as NSString
        let full = NSRange(location: 0, length: ns.length)
        var result: [Token] = []
        tokenRegex.enumerateMatches(in: input, range: full) { match, _, _ in
            guard let r = match?.range, r.location != NSNotFound else { return }
            result.append(Token(start: r.location,
                                 end: r.location + r.length,
                                 text: ns.substring(with: r)))
        }
        return result
    }

    private static let edgePunctuation =
        try! NSRegularExpression(pattern: "^[^\\p{L}\\p{N}]+|[^\\p{L}\\p{N}]+$")

    /// Strip leading/trailing non-letter/digit characters while leaving inner
    /// word(s) and internal apostrophes/hyphens intact: `"oblate,"` -> `oblate`,
    /// `"(don't)."` -> `don't`.
    static func trimEdgePunctuation(_ input: String) -> String {
        let ns = input as NSString
        return edgePunctuation.stringByReplacingMatches(
            in: input, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    }

    // PDFium delivers the hyphen it inserts at a line break as U+0002; a literal
    // soft hyphen (U+00AD) is treated the same. Stripping the marker plus hugging
    // whitespace/newline rejoins the word: "undis␂turbed" -> "undisturbed".
    // Embed the actual U+0002 / U+00AD scalars in the class (Swift string escapes,
    // one backslash) — ICU regex does NOT accept the "\u{XXXX}" brace escape, and a
    // "\\u{...}" regex escape here throws, crashing on the first selection.
    private static let pdfiumHyphen =
        try! NSRegularExpression(pattern: "[ \\t]*[\u{0002}\u{00AD}][ \\t]*(?:\\r?\\n)?[ \\t]*")
    // A word split by a *literal* visible hyphen at a line wrap.
    private static let wrapHyphen =
        try! NSRegularExpression(pattern: "(\\p{L})[-‐‑][ \\t]*(?:\\r?\\n)+[ \\t]*(\\p{Ll})")
    private static let lineBreaks =
        try! NSRegularExpression(pattern: "[ \\t]*(?:\\r?\\n)+[ \\t]*")

    /// Rewrite text selected across several lines into continuous text: rejoin a
    /// word hyphenated at a line wrap (letter before the hyphen, lower-case letter
    /// after — the signature of soft hyphenation), then collapse remaining line
    /// breaks to single spaces.
    static func joinWrappedLines(_ input: String) -> String {
        if input.isEmpty { return input }
        func replace(_ re: NSRegularExpression, _ s: String, _ tmpl: String) -> String {
            let ns = s as NSString
            return re.stringByReplacingMatches(
                in: s, range: NSRange(location: 0, length: ns.length), withTemplate: tmpl)
        }
        let joined = replace(pdfiumHyphen, input, "")
        let dehyphenated = replace(wrapHyphen, joined, "$1$2")
        return replace(lineBreaks, dehyphenated, " ")
    }
}
