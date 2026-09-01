import Foundation

/// A dictionary term prepared for matching: a sequence of normalized word tokens
/// plus the id of the owning dictionary entry.
struct MatchableTerm {
    let entryId: Int64
    let words: [String]
    /// Whether this (single-word) term also matches sub-word parts of longer words.
    let partial: Bool

    var wordCount: Int { words.count }

    /// Build from a raw term string (e.g. "well-known fact"). `partial` is honored
    /// only for single-word terms. Returns nil if the term has no word tokens.
    static func fromTerm(_ entryId: Int64, _ term: String, partial: Bool = false) -> MatchableTerm? {
        let words = TextNormalizer.tokenize(term).map { TextNormalizer.normalizeToken($0.text) }
        if words.isEmpty { return nil }
        return MatchableTerm(entryId: entryId, words: words, partial: partial && words.count == 1)
    }
}

/// A located occurrence of a term inside a page's text, as a half-open source
/// range `[start, end)` of UTF-16 code-unit indices into the page's full text.
struct TermMatch {
    let entryId: Int64
    let start: Int
    let end: Int
    var length: Int { end - start }
    var range: NSRange { NSRange(location: start, length: end - start) }
}

/// In-memory whole-word / multi-word phrase matcher — a direct port of the
/// Flutter app's `TermMatcher`.
///
/// Matching is done on word boundaries (so "cat" does not match inside
/// "category"). The matcher tokenizes the page text and, at each token, checks
/// whether any term whose first word equals that token continues to match.
final class TermMatcher {
    private var byFirstWord: [String: [MatchableTerm]] = [:]
    // Single-word sub-word terms, kept as parallel arrays (word, entry id).
    private var partialWords: [String] = []
    private var partialEntryIds: [Int64] = []
    private(set) var maxPhraseWordCount = 0

    init<S: Sequence>(_ terms: S) where S.Element == MatchableTerm {
        for term in terms {
            if term.words.isEmpty { continue }
            // Partial single-word terms use the sub-word path below (which also
            // covers their whole-word occurrences), so they are NOT added to the
            // whole-word index as well — that would double-match.
            if term.partial && term.wordCount == 1 {
                partialWords.append(term.words[0])
                partialEntryIds.append(term.entryId)
                continue
            }
            byFirstWord[term.words[0], default: []].append(term)
            if term.wordCount > maxPhraseWordCount { maxPhraseWordCount = term.wordCount }
        }
        // Longer phrases first so the most specific term is discovered first.
        for key in byFirstWord.keys {
            byFirstWord[key]!.sort { $0.wordCount > $1.wordCount }
        }
    }

    var isEmpty: Bool { byFirstWord.isEmpty && partialWords.isEmpty }

    /// A sub-word match is accepted when it abuts a connector (`-` or `'`) or a
    /// token edge.
    private static func isConnector(_ codeUnit: unichar) -> Bool {
        codeUnit == 0x2D /* - */ || codeUnit == 0x27 /* ' */
    }

    /// Find every occurrence of every term in `text`. Overlapping matches are all
    /// returned (e.g. both "bank" and "bank account").
    func findMatches(_ text: String) -> [TermMatch] {
        if isEmpty { return [] }
        let tokens = TextNormalizer.tokenize(text)
        let normalized = tokens.map { TextNormalizer.normalizeToken($0.text) }
        var matches: [TermMatch] = []
        for i in 0..<tokens.count {
            guard let candidates = byFirstWord[normalized[i]] else { continue }
            for term in candidates {
                let n = term.wordCount
                if i + n > tokens.count { continue }
                var ok = true
                var k = 1
                while k < n {
                    if normalized[i + k] != term.words[k] { ok = false; break }
                    k += 1
                }
                if ok {
                    matches.append(TermMatch(entryId: term.entryId,
                                             start: tokens[i].start,
                                             end: tokens[i + n - 1].end))
                }
            }
        }
        findPartialMatches(tokens, normalized, &matches)
        return matches
    }

    /// Sub-word matching for partial single-word terms: a term matches wherever it
    /// occurs inside a token aligned to at least one sub-word boundary — the
    /// token's start/end, or next to a hyphen/apostrophe connector.
    private func findPartialMatches(_ tokens: [Token], _ normalized: [String], _ out: inout [TermMatch]) {
        if partialWords.isEmpty { return }
        // Search on UTF-16 code units so an index into the normalized token maps
        // 1:1 onto the raw page offset (base + j), matching the Dart original.
        let words16 = partialWords.map { Array($0.utf16) }
        for i in 0..<tokens.count {
            let tok = Array(normalized[i].utf16)
            let tokLen = tok.count
            let base = tokens[i].start
            for w in 0..<words16.count {
                let word = words16[w]
                let wlen = word.count
                if wlen == 0 || wlen > tokLen { continue }
                var from = 0
                while true {
                    guard let j = indexOf(word, in: tok, from: from) else { break }
                    let endIdx = j + wlen
                    let leftOk = j == 0 || Self.isConnector(tok[j - 1])
                    let rightOk = endIdx == tokLen || Self.isConnector(tok[endIdx])
                    if leftOk || rightOk {
                        out.append(TermMatch(entryId: partialEntryIds[w],
                                             start: base + j, end: base + endIdx))
                    }
                    from = j + 1
                }
            }
        }
    }

    /// First index >= `from` at which `needle` occurs in `haystack` (UTF-16 units).
    private func indexOf(_ needle: [unichar], in haystack: [unichar], from: Int) -> Int? {
        let n = needle.count, h = haystack.count
        if n == 0 || n > h { return nil }
        var i = from
        while i + n <= h {
            var k = 0
            while k < n && haystack[i + k] == needle[k] { k += 1 }
            if k == n { return i }
            i += 1
        }
        return nil
    }
}
