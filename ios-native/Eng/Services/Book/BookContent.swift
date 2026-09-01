import Foundation

/// A run of text with inline styling (from `<b>/<i>/<a>` …). The renderer maps
/// these to font traits, link attributes, etc.
struct InlineRun {
    var text: String
    var bold = false
    var italic = false
    /// Raw href from an `<a>` (resolved to a target at render time), or nil.
    var link: String?
}

/// One block of reflowed content — a paragraph, heading, list item, blockquote,
/// image, or a chapter boundary. Every reflowable parser normalizes into these.
struct BookBlock {
    enum Kind {
        case heading1, heading2, heading3
        case paragraph
        case blockquote
        case listItem
        case image
        /// Start of a new spine item — rendered as spacing; anchors chapter jumps.
        case chapterBreak

        var isHeading: Bool { self == .heading1 || self == .heading2 || self == .heading3 }
    }

    var kind: Kind
    var runs: [InlineRun] = []
    /// Element ids within this block, for internal (#anchor) link targets.
    var anchorIds: [String] = []
    /// Image blocks: raw `src` (set by the HTML parser) then loaded bytes
    /// (resolved + filled by `EpubParser`).
    var imageSrc: String? = nil
    var imageData: Data? = nil
    /// List items: whether the enclosing list is ordered.
    var listOrdered = false
    var listIndex = 0
    /// chapterBreak markers: the spine file this chapter came from (for the TOC).
    var chapterFile: String? = nil

    /// Plain concatenated text — what the term matcher runs over.
    var plainText: String { runs.map(\.text).joined() }
}

/// A parsed reflowable document: blocks in reading order plus a title.
struct BookContent {
    let title: String?
    let blocks: [BookBlock]
}
