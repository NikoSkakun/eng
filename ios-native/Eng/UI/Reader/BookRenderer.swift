import UIKit

/// A highlighted term's location (UTF-16 range) -> its entry.
struct MatchSpan { let range: NSRange; let entryId: Int64 }
/// A hyperlink's location -> its raw href.
struct LinkSpan { let range: NSRange; let href: String }
/// A table-of-contents entry.
struct ChapterRef { var title: String; let offset: Int; let file: String }

/// The reflowable book rendered under the current reading style.
struct RenderedBook {
    let attributed: NSAttributedString
    let spans: [MatchSpan]                 // highlights, sorted by location
    let links: [LinkSpan]                  // sorted by location
    let anchors: [String: Int]             // anchor id -> char offset
    let chapterStarts: [String: Int]       // spine filename -> char offset
    let chapters: [ChapterRef]             // for the TOC
    var length: Int { attributed.length }
}

/// Builds the attributed string for a book: inline bold/italic, links, images,
/// lists, blockquotes, headings — plus saved-term highlights. `TermMatcher`
/// offsets are UTF-16, matching `NSAttributedString`/`NSRange`.
enum BookRenderer {
    static func render(_ content: BookContent, settings: AppSettings, matcher: TermMatcher,
                       contentWidth: CGFloat, colorForEntry: (Int64) -> UIColor) -> RenderedBook {
        let out = NSMutableAttributedString()
        var spans: [MatchSpan] = []
        var links: [LinkSpan] = []
        var anchors: [String: Int] = [:]
        var chapterStarts: [String: Int] = [:]
        var chapters: [ChapterRef] = []

        let base = CGFloat(settings.readerFontSize)
        let textColor = settings.readerTheme.text
        let secondary = settings.readerTheme.secondaryText
        let linkColor = UIColor.systemBlue
        let bodyFont = settings.readerFont.uiFont(size: base)

        func bodyParagraph() -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.lineSpacing = CGFloat(settings.readerLineSpacing)
            p.paragraphSpacing = base * 0.55
            p.alignment = settings.readerJustified ? .justified : .natural
            if settings.readerJustified { p.hyphenationFactor = 0.92 }
            return p
        }

        func appendRuns(_ block: BookBlock, font: UIFont, color: UIColor, paragraph: NSParagraphStyle, prefix: String? = nil) {
            let blockStart = out.length
            for id in block.anchorIds where anchors[id] == nil { anchors[id] = blockStart }

            if let prefix {
                out.append(NSAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]))
            }
            let textStart = out.length
            for run in block.runs {
                let f = inlineFont(base: font, bold: run.bold, italic: run.italic)
                var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: paragraph]
                if run.link != nil {
                    attrs[.foregroundColor] = linkColor
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                let runStart = out.length
                out.append(NSAttributedString(string: run.text, attributes: attrs))
                if let href = run.link {
                    links.append(LinkSpan(range: NSRange(location: runStart, length: (run.text as NSString).length), href: href))
                }
            }
            out.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))

            // Highlights: matcher runs over plainText; offsets shift past any prefix.
            if !matcher.isEmpty {
                for m in matcher.findMatches(block.plainText) {
                    let r = NSRange(location: textStart + m.start, length: m.end - m.start)
                    out.addAttribute(.backgroundColor, value: colorForEntry(m.entryId), range: r)
                    spans.append(MatchSpan(range: r, entryId: m.entryId))
                }
            }
        }

        for block in content.blocks {
            switch block.kind {
            case .chapterBreak:
                let p = NSMutableParagraphStyle()
                p.paragraphSpacing = out.length == 0 ? 0 : base * 1.8
                if out.length > 0 { out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p, .font: bodyFont])) }
                let file = block.chapterFile ?? "Chapter \(chapters.count + 1)"
                chapterStarts[file] = out.length
                chapters.append(ChapterRef(title: "", offset: out.length, file: file))

            case .image:
                appendImage(block, into: out, base: base, contentWidth: contentWidth)

            case .heading1, .heading2, .heading3:
                let level = block.kind == .heading1 ? 1 : (block.kind == .heading2 ? 2 : 3)
                let (font, para) = headingStyle(level, base: base, settings: settings)
                if let i = chapters.indices.last, chapters[i].title.isEmpty { chapters[i].title = block.plainText }
                appendRuns(block, font: font, color: textColor, paragraph: para)

            case .blockquote:
                let p = bodyParagraph()
                p.firstLineHeadIndent = base * 1.1; p.headIndent = base * 1.1; p.tailIndent = -base * 0.6
                appendRuns(block, font: bodyFont, color: secondary, paragraph: p)

            case .listItem:
                let p = bodyParagraph()
                p.firstLineHeadIndent = base * 0.4; p.headIndent = base * 1.7; p.paragraphSpacing = base * 0.25
                let marker = block.listOrdered ? "\(block.listIndex).  " : "•  "
                appendRuns(block, font: bodyFont, color: textColor, paragraph: p, prefix: marker)

            case .paragraph:
                appendRuns(block, font: bodyFont, color: textColor, paragraph: bodyParagraph())
            }
        }

        // Fill any chapter titles that had no heading.
        for i in chapters.indices where chapters[i].title.trimmingCharacters(in: .whitespaces).isEmpty {
            let stem = (chapters[i].file as NSString).deletingPathExtension
                .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            chapters[i].title = stem.isEmpty ? "Chapter \(i + 1)" : stem
        }

        spans.sort { $0.range.location < $1.range.location }
        links.sort { $0.range.location < $1.range.location }
        // A single-spine book needs no chapter list.
        let toc = chapters.count > 1 ? chapters : []
        return RenderedBook(attributed: out, spans: spans, links: links, anchors: anchors,
                            chapterStarts: chapterStarts, chapters: toc)
    }

    // MARK: helpers

    private static func inlineFont(base: UIFont, bold: Bool, italic: Bool) -> UIFont {
        guard bold || italic else { return base }
        var traits = base.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        if let d = base.fontDescriptor.withSymbolicTraits(traits) { return UIFont(descriptor: d, size: base.pointSize) }
        return base
    }

    private static func headingStyle(_ level: Int, base: CGFloat, settings: AppSettings) -> (UIFont, NSParagraphStyle) {
        let mult: CGFloat = level == 1 ? 1.5 : (level == 2 ? 1.28 : 1.12)
        let weight: UIFont.Weight = level == 1 ? .bold : .semibold
        let p = NSMutableParagraphStyle()
        p.lineSpacing = CGFloat(settings.readerLineSpacing) * 0.6
        p.paragraphSpacingBefore = base * (level == 1 ? 1.1 : 0.8)
        p.paragraphSpacing = base * 0.3
        return (settings.readerFont.uiFont(size: base * mult, weight: weight), p)
    }

    private static func appendImage(_ block: BookBlock, into out: NSMutableAttributedString, base: CGFloat, contentWidth: CGFloat) {
        guard let data = block.imageData, let img = UIImage(data: data) else { return }
        let maxW = max(120, contentWidth)
        let scale = min(1, img.size.width > 0 ? maxW / img.size.width : 1)
        let att = NSTextAttachment()
        att.image = img
        att.bounds = CGRect(x: 0, y: 0, width: img.size.width * scale, height: img.size.height * scale)
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        center.paragraphSpacingBefore = base * 0.6
        center.paragraphSpacing = base * 0.6
        let s = NSMutableAttributedString(attachment: att)
        s.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: s.length))
        out.append(s)
        out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: center]))
    }
}
