import Foundation

/// Parses an EPUB into `BookContent`: unzip → `META-INF/container.xml` → the OPF
/// package (manifest + spine) → each spine XHTML → text blocks, in reading order.
///
/// XML is read with targeted regexes rather than a full parser — enough for the
/// container/OPF shape virtually every EPUB uses. Chapters are separated by a
/// `.chapterBreak` block.
enum EpubParser {
    static func parse(fileURL: URL) -> BookContent? {
        guard let data = try? Data(contentsOf: fileURL), let zip = ZipArchive(data: data) else { return nil }

        // 1. container.xml -> OPF path.
        guard let container = zip.utf8("META-INF/container.xml"),
              let opfPath = firstGroup(container, #"full-path=\"([^\"]+)\""#) else { return nil }

        // 2. OPF package document.
        guard let opf = zip.utf8(opfPath) else { return nil }
        let opfDir = (opfPath as NSString).deletingLastPathComponent

        let title = firstGroup(opf, #"<dc:title[^>]*>(.*?)</dc:title>"#, dotAll: true)
            .map { HtmlText.plainText($0) }

        // manifest: id -> href
        var hrefById: [String: String] = [:]
        for m in allMatches(opf, #"<item\b([^>]*)>"#) {
            guard let id = attr(m, "id"), let href = attr(m, "href") else { continue }
            hrefById[id] = href
        }
        // spine order: idref list
        let spine = allMatches(opf, #"<itemref\b([^>]*)>"#).compactMap { attr($0, "idref") }

        // 3. Each spine item -> resolved zip path -> blocks.
        var blocks: [BookBlock] = []
        for (i, idref) in spine.enumerated() {
            guard let href = hrefById[idref] else { continue }
            let path = resolve(href, relativeTo: opfDir)
            guard let xhtml = zip.utf8(path) else { continue }
            if i > 0 { blocks.append(BookBlock(kind: .chapterBreak, text: "")) }
            blocks.append(contentsOf: HtmlText.blocks(from: xhtml))
        }
        guard !blocks.isEmpty else { return nil }
        return BookContent(title: title?.isEmpty == false ? title : nil, blocks: blocks)
    }

    /// Number of spine documents, for a quick library subtitle. Cheap-ish: only
    /// parses container + OPF, not the chapters.
    static func chapterCount(fileURL: URL) -> Int {
        guard let data = try? Data(contentsOf: fileURL), let zip = ZipArchive(data: data),
              let container = zip.utf8("META-INF/container.xml"),
              let opfPath = firstGroup(container, #"full-path=\"([^\"]+)\""#),
              let opf = zip.utf8(opfPath) else { return 0 }
        return allMatches(opf, #"<itemref\b([^>]*)>"#).count
    }

    // MARK: path + xml helpers

    /// Resolve `href` (from the OPF) against the OPF's directory, collapsing
    /// `./` and `../`. Percent-decodes so `chapter%201.xhtml` matches the entry.
    private static func resolve(_ href: String, relativeTo dir: String) -> String {
        let cleaned = href.removingPercentEncoding ?? href
        var parts = dir.isEmpty ? [] : dir.components(separatedBy: "/")
        for comp in cleaned.components(separatedBy: "/") {
            if comp == "." || comp.isEmpty { continue }
            if comp == ".." { if !parts.isEmpty { parts.removeLast() } ; continue }
            parts.append(comp)
        }
        return parts.joined(separator: "/")
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

    private static func allMatches(_ s: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }
}

private extension ZipArchive {
    func utf8(_ name: String) -> String? { data(for: name).map { String(decoding: $0, as: UTF8.self) } }
}
