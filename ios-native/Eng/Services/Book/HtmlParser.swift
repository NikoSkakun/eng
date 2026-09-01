import Foundation

/// A small, dependency-free XHTML tokenizer that turns a chapter into
/// `BookBlock`s with inline styling (bold/italic), links, images, lists,
/// blockquotes and heading levels. It is deliberately lenient: CSS is ignored
/// and unknown inline tags are treated as plain text.
enum HtmlParser {
    static func parse(_ html: String) -> [BookBlock] {
        // Strip the parts we never render.
        var s = html
        s = HtmlText.replace(s, #"<\?xml[^>]*\?>"#, "")
        s = HtmlText.replace(s, #"<!DOCTYPE[^>]*>"#, "", caseInsensitive: true)
        s = HtmlText.replace(s, #"<!--.*?-->"#, "", dotAll: true)
        for tag in ["head", "script", "style"] {
            s = HtmlText.replace(s, "<\(tag)\\b[^>]*>.*?</\(tag)>", "", dotAll: true, caseInsensitive: true)
        }
        if let body = firstGroup(s, #"<body\b[^>]*>(.*?)</body>"#, dotAll: true) { s = body }

        let ns = s as NSString
        let tagRe = try! NSRegularExpression(pattern: "<[^>]+>", options: [.dotMatchesLineSeparators])

        var blocks: [BookBlock] = []
        var current: BookBlock?
        var runText = ""
        var bold = 0, italic = 0
        var linkHref: String?
        var quoteDepth = 0
        var listStack: [(ordered: Bool, count: Int)] = []
        var pendingIds: [String] = []

        func addId(_ id: String) {
            if current != nil { current!.anchorIds.append(id) } else { pendingIds.append(id) }
        }
        func ensureBlock(_ kind: BookBlock.Kind) {
            if current == nil {
                current = BookBlock(kind: quoteDepth > 0 ? .blockquote : kind, anchorIds: pendingIds)
                pendingIds = []
            }
        }
        func flushRun() {
            if runText.isEmpty { return }
            if current == nil {
                if runText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { runText = ""; return }
                ensureBlock(.paragraph)
            }
            current!.runs.append(InlineRun(text: runText, bold: bold > 0, italic: italic > 0, link: linkHref))
            runText = ""
        }
        func flushBlock() {
            flushRun()
            guard var b = current else { return }
            current = nil
            b.runs = collapse(b.runs)
            if !b.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(b)
            } else if !b.anchorIds.isEmpty {
                pendingIds = b.anchorIds + pendingIds   // carry anchors onto the next block
            }
        }
        func startBlock(_ kind: BookBlock.Kind, ordered: Bool = false, index: Int = 0) {
            flushBlock()
            current = BookBlock(kind: quoteDepth > 0 && kind == .paragraph ? .blockquote : kind,
                                anchorIds: pendingIds, listOrdered: ordered, listIndex: index)
            pendingIds = []
        }

        var cursor = 0
        tagRe.enumerateMatches(in: s, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            if m.range.location > cursor {
                runText += HtmlText.decodeEntities(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            cursor = m.range.location + m.range.length
            let tag = ns.substring(with: m.range)
            let inner = String(tag.dropFirst().dropLast())
            let isClosing = inner.hasPrefix("/")
            let after = isClosing ? String(inner.dropFirst()) : inner
            let name = String(after.prefix { $0.isLetter || $0.isNumber }).lowercased()
            if name.isEmpty { return }

            if !isClosing {
                if let id = attr(after, "id") { addId(id) }
                if name == "a", let anchorName = attr(after, "name") { addId(anchorName) }
            }

            switch (isClosing, name) {
            case (false, "p"), (false, "div"): startBlock(.paragraph)
            case (false, "h1"): startBlock(.heading1)
            case (false, "h2"): startBlock(.heading2)
            case (false, "h3"), (false, "h4"), (false, "h5"), (false, "h6"): startBlock(.heading3)
            case (false, "blockquote"): flushBlock(); quoteDepth += 1
            case (false, "ul"): listStack.append((false, 0))
            case (false, "ol"): listStack.append((true, 0))
            case (false, "li"):
                let ordered = listStack.last?.ordered ?? false
                if !listStack.isEmpty { listStack[listStack.count - 1].count += 1 }
                startBlock(.listItem, ordered: ordered, index: listStack.last?.count ?? 0)
            case (false, "br"): runText += " "
            case (false, "hr"): flushBlock()
            case (false, "img"):
                flushBlock()
                var b = BookBlock(kind: .image, anchorIds: pendingIds)
                b.imageSrc = attr(after, "src")
                pendingIds = []
                if b.imageSrc != nil { blocks.append(b) }
            // Flush before every inline-style change so each run captures the
            // style that was active while its text accumulated.
            case (false, "b"), (false, "strong"): flushRun(); bold += 1
            case (false, "i"), (false, "em"), (false, "cite"): flushRun(); italic += 1
            case (false, "a"): flushRun(); linkHref = attr(after, "href")

            case (true, "p"), (true, "div"), (true, "h1"), (true, "h2"), (true, "h3"),
                 (true, "h4"), (true, "h5"), (true, "h6"), (true, "li"): flushBlock()
            case (true, "blockquote"): flushBlock(); quoteDepth = max(0, quoteDepth - 1)
            case (true, "ul"), (true, "ol"): if !listStack.isEmpty { listStack.removeLast() }
            case (true, "b"), (true, "strong"): flushRun(); bold = max(0, bold - 1)
            case (true, "i"), (true, "em"), (true, "cite"): flushRun(); italic = max(0, italic - 1)
            case (true, "a"): flushRun(); linkHref = nil
            default: break
            }
        }
        if cursor < ns.length { runText += HtmlText.decodeEntities(ns.substring(from: cursor)) }
        flushBlock()
        return blocks
    }

    // MARK: helpers

    /// Collapse whitespace within each run and trim the block's outer edges.
    private static func collapse(_ runs: [InlineRun]) -> [InlineRun] {
        var out = runs.map { r -> InlineRun in
            var r = r
            r.text = HtmlText.replace(r.text, #"[ \t\r\n\f]+"#, " ")
            return r
        }
        if var first = out.first { first.text = String(first.text.drop { $0 == " " }); out[0] = first }
        if var last = out.last {
            while last.text.hasSuffix(" ") { last.text.removeLast() }
            out[out.count - 1] = last
        }
        return out.filter { !$0.text.isEmpty }
    }

    private static func attr(_ tag: String, _ name: String) -> String? {
        firstGroup(tag, "\\b\(name)\\s*=\\s*\"([^\"]*)\"") ?? firstGroup(tag, "\\b\(name)\\s*=\\s*'([^']*)'")
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
