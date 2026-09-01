import UIKit

/// A highlighted term's location in the rendered book (UTF-16 range) → its entry.
struct MatchSpan { let range: NSRange; let entryId: Int64 }

/// The reflowable book turned into one styled attributed string plus the match
/// spans (sorted by location) used for tap hit-testing.
struct RenderedBook {
    let attributed: NSAttributedString
    let spans: [MatchSpan]
    /// Total UTF-16 length, for reading-progress math.
    var length: Int { attributed.length }
}

/// Builds the attributed string for a book under the current reading style, and
/// paints saved-term highlights. Offsets from `TermMatcher` are UTF-16 code
/// units, which line up 1:1 with `NSAttributedString`/`NSRange`.
enum BookRenderer {
    static func render(_ content: BookContent, settings: AppSettings,
                       matcher: TermMatcher, colorForEntry: (Int64) -> UIColor) -> RenderedBook {
        let out = NSMutableAttributedString()
        var spans: [MatchSpan] = []

        let base = CGFloat(settings.readerFontSize)
        let textColor = settings.readerTheme.text
        let bodyFont = settings.readerFont.uiFont(size: base)

        let bodyPara = NSMutableParagraphStyle()
        bodyPara.lineSpacing = CGFloat(settings.readerLineSpacing)
        bodyPara.paragraphSpacing = base * 0.55
        bodyPara.alignment = settings.readerJustified ? .justified : .natural
        if settings.readerJustified { bodyPara.hyphenationFactor = 0.92 }

        func headingStyle(_ level: Int) -> (UIFont, NSParagraphStyle) {
            let mult: CGFloat = level == 1 ? 1.5 : (level == 2 ? 1.28 : 1.12)
            let weight: UIFont.Weight = level == 1 ? .bold : .semibold
            let p = NSMutableParagraphStyle()
            p.lineSpacing = CGFloat(settings.readerLineSpacing) * 0.6
            p.paragraphSpacingBefore = base * (level == 1 ? 1.1 : 0.8)
            p.paragraphSpacing = base * 0.3
            return (settings.readerFont.uiFont(size: base * mult, weight: weight), p)
        }

        let chapterSpacer = NSMutableParagraphStyle()
        chapterSpacer.paragraphSpacing = base * 1.6

        for block in content.blocks {
            if block.kind == .chapterBreak {
                out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: chapterSpacer, .font: bodyFont]))
                continue
            }
            let font: UIFont
            let para: NSParagraphStyle
            switch block.kind {
            case .heading1: (font, para) = headingStyle(1)
            case .heading2: (font, para) = headingStyle(2)
            case .heading3: (font, para) = headingStyle(3)
            default: font = bodyFont; para = bodyPara
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: textColor, .paragraphStyle: para,
            ]
            let blockStart = out.length
            out.append(NSAttributedString(string: block.text + "\n", attributes: attrs))

            if !matcher.isEmpty {
                for m in matcher.findMatches(block.text) {
                    let r = NSRange(location: blockStart + m.start, length: m.end - m.start)
                    out.addAttribute(.backgroundColor, value: colorForEntry(m.entryId), range: r)
                    spans.append(MatchSpan(range: r, entryId: m.entryId))
                }
            }
        }
        spans.sort { $0.range.location < $1.range.location }
        return RenderedBook(attributed: out, spans: spans)
    }
}
