import SwiftUI
import UIKit

/// Full-screen reflowable (EPUB) reader: parses the book, lays it out with the
/// current reading style, auto-highlights saved terms, shows a translation
/// callout on tapping a highlight, and offers an "Add" affordance for selected
/// text. Position and reading style persist.
struct TextReaderView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let document: LibraryDocument

    @StateObject private var coord = TextReaderCoordinator()
    @State private var addSeed: TextSeed?
    @State private var showStyle = false
    @State private var showTOC = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(coord.theme.background).ignoresSafeArea()

                BookTextView(coordinator: coord)
                    .ignoresSafeArea(edges: .bottom)
                    .opacity(coord.loading ? 0 : 1)
                    .overlay {
                        GeometryReader { geo in
                            if let wp = coord.wordPopup, let entry = app.entry(id: wp.entryId) {
                                WordTranslationPopup(entry: entry, anchor: wp.rect, container: geo.size)
                                    .id(wp.id)
                                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)))
                            }
                        }
                        .allowsHitTesting(false)
                        .animation(.snappy(duration: 0.16), value: coord.wordPopup?.id)
                    }

                if coord.loading {
                    ProgressView().controlSize(.large)
                } else if coord.failed {
                    ContentUnavailableView("Couldn’t open this book", systemImage: "book.closed",
                        description: Text("The EPUB could not be parsed."))
                }

                if let text = coord.selection, !text.isEmpty {
                    Button {
                        addSeed = TextSeed(text: text)
                        coord.clearSelection()
                    } label: {
                        Label("Add “\(text.prefix(28))”", systemImage: "plus.circle.fill")
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.thinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.tint.opacity(0.5)))
                    }
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.18), value: coord.selection)
            .navigationTitle(coord.title ?? document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { coord.saveProgress(); dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(coord.progressLabel).font(.footnote).foregroundStyle(.secondary)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if coord.hasChapters {
                        Button { showTOC = true } label: { Image(systemName: "list.bullet") }
                            .disabled(coord.loading)
                    }
                    Button { showStyle = true } label: { Image(systemName: "textformat.size") }
                        .disabled(coord.loading)
                }
            }
        }
        .onAppear { coord.start(app: app, document: document) }
        .onDisappear { coord.saveProgress() }
        .onChange(of: app.dictionaryRevision) { coord.reflow() }   // dictionary OR reading-style change
        .onChange(of: scenePhase) { if scenePhase != .active { coord.saveProgress() } }
        .sheet(item: $addSeed) { seed in AddEntrySheet(seedText: seed.text, documentId: document.id) }
        .sheet(isPresented: $showStyle) {
            ReadingSettingsSheet().presentationDetents([.height(430), .large])
        }
        .sheet(isPresented: $showTOC) {
            ChaptersSheet(chapters: coord.chapters) { coord.jumpToChapter($0) }
        }
    }
}

/// Table of contents — jump to a chapter.
struct ChaptersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [ChapterRef]
    let onSelect: (ChapterRef) -> Void

    var body: some View {
        NavigationStack {
            List(Array(chapters.enumerated()), id: \.offset) { i, ch in
                Button {
                    onSelect(ch); dismiss()
                } label: {
                    Text(ch.title.isEmpty ? "Chapter \(i + 1)" : ch.title)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Surfaces the coordinator's `UITextView`.
private struct BookTextView: UIViewRepresentable {
    let coordinator: TextReaderCoordinator
    func makeUIView(context: Context) -> UITextView { coordinator.textView }
    func updateUIView(_ uiView: UITextView, context: Context) {}
}

/// Owns the text view, parses the book, lays it out, and drives highlighting,
/// hit-testing, selection and progress.
@MainActor
final class TextReaderCoordinator: NSObject, ObservableObject {
    // A TextKit 1 stack: predictable layoutManager coordinates for hit-testing.
    let textView: UITextView = {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let v = UITextView(frame: .zero, textContainer: container)
        v.isEditable = false
        v.isSelectable = true
        v.alwaysBounceVertical = true
        v.textContainerInset = UIEdgeInsets(top: 18, left: 22, bottom: 48, right: 22)
        return v
    }()

    @Published var selection: String?
    @Published var wordPopup: WordPopup?
    @Published var loading = true
    @Published var failed = false
    @Published var title: String?
    @Published var progressLabel = ""
    @Published var theme: ReaderTheme = .system
    @Published var chapters: [ChapterRef] = []
    var hasChapters: Bool { chapters.count > 1 }

    private weak var app: AppState?
    private var document: LibraryDocument?
    private var content: BookContent?
    private var matcher = TermMatcher([])
    private var rendered: RenderedBook?
    private var started = false
    private var restored = false
    private var pendingOffset: Int?          // char offset to restore once laid out
    private var scrollObs: NSKeyValueObservation?
    private var popupAnchorOffset: CGFloat = 0

    // MARK: lifecycle

    func start(app: AppState, document: LibraryDocument) {
        guard !started else { return }
        started = true
        self.app = app
        self.document = document
        self.theme = app.settings.readerTheme
        applyStyleChrome()

        textView.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        textView.addGestureRecognizer(tap)
        scrollObs = textView.observe(\.contentOffset, options: [.new]) { [weak self] tv, _ in
            let y = tv.contentOffset.y
            DispatchQueue.main.async { self?.onScroll(y) }
        }

        // Restore the saved reading position and "zoom" (font size). Apply the
        // saved size to the (global) reading settings first so the book reopens at
        // the size it was read; loading is still true, so no premature reflow.
        if let saved = document.epubViewState {
            pendingOffset = max(0, saved.charOffset)
            if saved.fontSize >= kReaderFontSizeRange.lowerBound && saved.fontSize <= kReaderFontSizeRange.upperBound {
                app.mutateSettings { $0.readerFontSize = saved.fontSize }
            }
        } else {
            // Older builds stored just the char offset in `lastPage`.
            pendingOffset = (document.lastOpenedAt != nil) ? max(0, document.lastPage) : nil
        }

        let url = document.fileURL
        Task { [weak self] in
            let parsed = await Task.detached { EpubParser.parse(fileURL: url) }.value
            guard let self else { return }
            guard let parsed else { self.loading = false; self.failed = true; return }
            self.content = parsed
            self.title = parsed.title
            self.reflow(restoreOffset: self.pendingOffset ?? 0)
            self.loading = false
        }
    }

    /// Re-render with the current reading style + dictionary, preserving the
    /// reading position. Called on style changes and dictionary edits.
    func reflow() {
        guard content != nil, !loading else { return }
        reflow(restoreOffset: topVisibleCharOffset())
    }

    private func reflow(restoreOffset offset: Int) {
        guard let content, let app, let document else { return }
        theme = app.settings.readerTheme
        matcher = app.matcher(documentId: document.id)
        let inset = app.settings.readerMargin.inset
        let usable = (textView.bounds.width > 0 ? textView.bounds.width : UIScreen.main.bounds.width) - inset * 2
        let r = BookRenderer.render(content, settings: app.settings, matcher: matcher, contentWidth: usable) { [weak self] id in
            self?.color(forEntry: id) ?? UIColor(argb: kDefaultHighlightColor)
        }
        rendered = r
        chapters = r.chapters
        textView.attributedText = r.attributed
        applyStyleChrome()
        restored = false
        // Layout must exist before we can scroll to a character; force it, then jump.
        textView.layoutIfNeeded()
        scroll(toCharOffset: offset)
        restored = true
        updateProgress()
    }

    private func applyStyleChrome() {
        guard let s = app?.settings else { textView.backgroundColor = theme.background; return }
        textView.backgroundColor = s.readerTheme.background
        textView.textContainerInset = UIEdgeInsets(top: 18, left: s.readerMargin.inset, bottom: 48, right: s.readerMargin.inset)
        textView.indicatorStyle = s.readerTheme.isDarkAppearance ? .white : .default
        textView.tintColor = UIColor(argb: kDefaultHighlightColor)
    }

    // MARK: position

    func saveProgress() {
        guard restored, let app, let document else { return }
        let off = topVisibleCharOffset()
        let len = rendered?.length ?? 0
        let state = EpubViewState(charOffset: off, fontSize: app.settings.readerFontSize,
                                  progress: len > 0 ? Double(off) / Double(len) : 0)
        app.saveProgress(documentId: document.id, page: off, viewMatrix: state.json)
    }

    /// Jump to a chapter (from the TOC), scrolling smoothly.
    func jumpToChapter(_ ref: ChapterRef) { wordPopup = nil; scroll(toCharOffset: ref.offset, animated: true) }

    private func onScroll(_ y: CGFloat) {
        updateProgress()
        if wordPopup != nil, abs(y - popupAnchorOffset) > 12 { wordPopup = nil }
    }

    private func updateProgress() {
        let len = rendered?.length ?? 0
        guard len > 0 else { progressLabel = ""; return }
        let pct = Int((Double(topVisibleCharOffset()) / Double(len) * 100).rounded())
        progressLabel = "\(min(max(pct, 0), 100))%"
    }

    /// Character index at the top-left of the visible area (content coordinates).
    private func topVisibleCharOffset() -> Int {
        guard textView.textStorage.length > 0 else { return 0 }
        let inset = textView.textContainerInset
        let p = CGPoint(x: 2, y: max(0, textView.contentOffset.y - inset.top) + 2)
        let glyph = textView.layoutManager.glyphIndex(for: p, in: textView.textContainer)
        return textView.layoutManager.characterIndexForGlyph(at: glyph)
    }

    private func scroll(toCharOffset offset: Int, animated: Bool = false) {
        let len = textView.textStorage.length
        guard len > 0 else { return }
        if offset <= 0 { textView.setContentOffset(.init(x: 0, y: -textView.adjustedContentInset.top), animated: animated); return }
        let rect = contentRect(forCharRange: NSRange(location: min(offset, len - 1), length: 1))
        let maxY = max(-textView.adjustedContentInset.top, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
        let y = min(max(rect.minY - textView.textContainerInset.top, -textView.adjustedContentInset.top), maxY)
        textView.setContentOffset(.init(x: 0, y: y), animated: animated)
    }

    /// Bounding rect of a character range in the text view's CONTENT coordinates.
    private func contentRect(forCharRange range: NSRange) -> CGRect {
        let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var r = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
        r.origin.x += textView.textContainerInset.left
        r.origin.y += textView.textContainerInset.top
        return r
    }

    private func color(forEntry id: Int64) -> UIColor {
        let argb = app?.entry(id: id)?.colorValue ?? app?.settings.highlightColor ?? kDefaultHighlightColor
        return UIColor(argb: argb)
    }

    func clearSelection() { textView.selectedTextRange = nil; selection = nil }

    // MARK: tap

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard let rendered, textView.textStorage.length > 0 else { wordPopup = nil; return }
        let loc = gr.location(in: textView)   // content coordinates
        let inset = textView.textContainerInset
        let cp = CGPoint(x: loc.x - inset.left, y: loc.y - inset.top)
        let glyph = textView.layoutManager.glyphIndex(for: cp, in: textView.textContainer)
        let idx = textView.layoutManager.characterIndexForGlyph(at: glyph)
        // Only accept a tap that actually lands on the character (not a far snap).
        guard contentRect(forCharRange: NSRange(location: idx, length: 1)).insetBy(dx: -6, dy: -4).contains(loc) else {
            wordPopup = nil; return
        }
        // A hyperlink wins over a highlight (explicit navigation intent).
        if let link = linkContaining(idx) ?? linkContaining(idx - 1) { wordPopup = nil; follow(link.href); return }
        guard let span = spanContaining(idx) ?? spanContaining(idx - 1) else { wordPopup = nil; return }
        var r = contentRect(forCharRange: span.range)
        r.origin.y -= textView.contentOffset.y      // content -> visible
        r.origin.x -= textView.contentOffset.x
        popupAnchorOffset = textView.contentOffset.y
        wordPopup = WordPopup(entryId: span.entryId, rect: r)
    }

    /// Shortest highlighted span covering `idx` (most specific for overlaps).
    private func spanContaining(_ idx: Int) -> MatchSpan? {
        guard idx >= 0, let spans = rendered?.spans else { return nil }
        return spans.filter { $0.range.location <= idx && idx < $0.range.location + $0.range.length }
                    .min { $0.range.length < $1.range.length }
    }

    private func linkContaining(_ idx: Int) -> LinkSpan? {
        guard idx >= 0, let links = rendered?.links else { return nil }
        return links.first { $0.range.location <= idx && idx < $0.range.location + $0.range.length }
    }

    /// Follow a link: open external URLs in the browser; navigate internal ones
    /// (an anchor id, or another chapter file) within the book.
    private func follow(_ href: String) {
        let scheme = URL(string: href)?.scheme?.lowercased()
        if scheme == "http" || scheme == "https" || scheme == "mailto" {
            if let url = URL(string: href) { UIApplication.shared.open(url) }
            return
        }
        guard let rendered else { return }
        let fragment = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).count > 1
            ? String(href.split(separator: "#", maxSplits: 1)[1]) : nil
        let pathPart = String(href.split(separator: "#", maxSplits: 1)[0])
        if let fragment, let off = rendered.anchors[fragment] { scroll(toCharOffset: off, animated: true); return }
        let file = (pathPart as NSString).lastPathComponent
        if let off = rendered.chapterStarts[file] { scroll(toCharOffset: off, animated: true) }
    }
}

extension TextReaderCoordinator: UITextViewDelegate {
    func textViewDidChangeSelection(_ tv: UITextView) {
        guard let range = tv.selectedTextRange, !range.isEmpty, let raw = tv.text(in: range) else {
            selection = nil; return
        }
        let joined = TextNormalizer.joinWrappedLines(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        selection = joined.isEmpty ? nil : joined
        if selection != nil { wordPopup = nil }
    }
}

extension TextReaderCoordinator: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
