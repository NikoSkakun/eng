import Foundation

/// One block of reflowed text — a paragraph or a heading. Every reflowable
/// parser normalizes its format into a list of these, so the text reader only
/// needs to understand `BookContent` (mirrors the Flutter app's `BookBlock`).
struct BookBlock {
    enum Kind {
        case heading1, heading2, heading3
        case paragraph
        /// A chapter boundary (start of a new spine item) — rendered as spacing.
        case chapterBreak

        var isHeading: Bool { self == .heading1 || self == .heading2 || self == .heading3 }
    }

    let kind: Kind
    let text: String
}

/// A parsed reflowable document: its blocks in reading order plus a title.
struct BookContent {
    let title: String?
    let blocks: [BookBlock]

    var isEmpty: Bool { blocks.allSatisfy { $0.text.isEmpty && $0.kind != .chapterBreak } }
}
