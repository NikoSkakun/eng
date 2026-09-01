import SwiftUI
import PDFKit
import UIKit

/// Full-screen PDF reader: renders the document, auto-highlights saved terms,
/// opens a popup when a highlight is tapped, and offers an "Add" affordance for
/// the current text selection.
struct ReaderView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let document: LibraryDocument

    @StateObject private var coord = ReaderCoordinator()
    @State private var addSeed: TextSeed?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PDFKitView(coordinator: coord)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay {
                        // Inline translation callout anchored above the tapped word
                        // (same coordinate space as the PDFView). Purely visual —
                        // taps pass straight through to dismiss / re-tap.
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
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { coord.saveProgress(); dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(coord.pageLabel).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { coord.start(app: app, document: document) }
        .onDisappear { coord.saveProgress() }
        .onChange(of: app.dictionaryRevision) { coord.rebuildMatcher() }
        .onChange(of: scenePhase) { if scenePhase != .active { coord.saveProgress() } }
        .sheet(item: $addSeed) { seed in
            AddEntrySheet(seedText: seed.text, documentId: document.id)
        }
    }
}

struct TextSeed: Identifiable { let id = UUID(); let text: String }

/// A tapped highlighted word: which entry, and where it sits in PDFView space.
struct WordPopup: Equatable { let id = UUID(); let entryId: Int64; let rect: CGRect }

/// Small translation callout shown above (or below, near the top) a tapped word.
private struct WordTranslationPopup: View {
    let entry: DictionaryEntry
    let anchor: CGRect       // the word's rect in container coordinates
    let container: CGSize
    @State private var size: CGSize = .zero

    private var maxWidth: CGFloat { min(320, max(140, container.width - 32)) }

    var body: some View {
        // Vertical anchoring needs no measurement: occupy the strip of space above
        // the word and bottom-align inside it, so the bubble's bottom edge always
        // lands just above the word whatever its height. (Gating visibility on a
        // measured size risked never showing at all.)
        let gap: CGFloat = 10
        let spaceAbove = anchor.minY - gap
        // Flip below the word when the bubble wouldn't fit above it.
        let above = spaceAbove > (size.height > 0 ? size.height + 8 : 72)
        let stripY: CGFloat = above ? 0 : anchor.maxY + gap
        let stripH: CGFloat = above ? max(1, spaceAbove)
                                    : max(1, container.height - anchor.maxY - gap)
        bubble
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: PopupSizeKey.self, value: g.size)
            })
            .onPreferenceChange(PopupSizeKey.self) { size = $0 }
            .frame(width: container.width, height: stripH, alignment: above ? .bottom : .top)
            .offset(x: xOffset, y: stripY)
    }

    /// Slide from centre toward the word, clamped on-screen. Falls back to centred
    /// until the width is known, so the bubble is never hidden.
    private var xOffset: CGFloat {
        guard size.width > 0 else { return 0 }
        let desired = anchor.midX - container.width / 2
        let limit = max(0, (container.width - size.width) / 2 - 8)
        return min(max(desired, -limit), limit)
    }

    @ViewBuilder private var bubble: some View {
        let translations = entry.allTranslations
        VStack(alignment: .leading, spacing: 3) {
            if translations.isEmpty {
                Text(entry.definition?.isEmpty == false ? entry.definition! : entry.term)
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(Array(translations.enumerated()), id: \.offset) { i, t in
                    Text(t)
                        .font(i == 0 ? .callout.weight(.semibold) : .subheadline)
                        .foregroundStyle(i == 0 ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }

}

private struct PopupSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// UIViewRepresentable that surfaces the coordinator's `PDFView`.
private struct PDFKitView: UIViewRepresentable {
    let coordinator: ReaderCoordinator
    func makeUIView(context: Context) -> PDFView { coordinator.pdfView }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}

/// `PDFView` with a one-shot hook after the first real layout pass — the earliest
/// moment a saved zoom + position can be applied reliably (before layout the
/// scroll geometry isn't established, and `autoScales` would override a manually
/// set `scaleFactor`).
final class ReaderPDFView: PDFView {
    var onFirstLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, let hook = onFirstLayout {
            onFirstLayout = nil
            hook()
        }
    }
}

/// Owns the `PDFView`, the matcher, and the per-page match cache; drives
/// highlighting, tap hit-testing, selection surfacing, and progress saving.
@MainActor
final class ReaderCoordinator: NSObject, ObservableObject {
    let pdfView: ReaderPDFView = {
        let v = ReaderPDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .systemBackground
        v.usePageViewController(false)
        return v
    }()

    @Published var selection: String?
    @Published var pageLabel = ""
    /// The currently shown inline translation callout (nil = none).
    @Published var wordPopup: WordPopup?

    private weak var app: AppState?
    private var document: LibraryDocument?
    private var pdfDocument: PDFDocument?
    private var matcher = TermMatcher([])
    private var pageMatches: [Int: [TermMatch]] = [:]
    private var pageSelections: [Int: [PDFSelection]] = [:]
    private var started = false
    private var restored = false
    private var scrollObs: NSKeyValueObservation?
    private weak var docScrollView: UIScrollView?
    /// Scroll offset when the callout was shown — the baseline for dismissing it.
    private var popupAnchorOffset: CGPoint = .zero

    private func dismissPopupIfScrolled(to offset: CGPoint) {
        guard wordPopup != nil else { return }
        if abs(offset.y - popupAnchorOffset.y) > 12 || abs(offset.x - popupAnchorOffset.x) > 12 {
            wordPopup = nil
        }
    }

    func start(app: AppState, document: LibraryDocument) {
        guard !started else { return }
        started = true
        self.app = app
        self.document = document

        guard let doc = PDFDocument(url: document.fileURL) else { pageLabel = "—"; return }
        pdfDocument = doc
        pdfView.document = doc

        // Restore the exact saved view (page + position + zoom), or fall back to
        // the last page, once the view has real bounds.
        let saved = document.viewState
        let fallbackPage = max(0, min(document.lastPage - 1, doc.pageCount - 1))
        pdfView.onFirstLayout = { [weak self] in
            self?.restoreView(saved, fallbackPage: fallbackPage)
        }

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: pdfView)
        nc.addObserver(self, selector: #selector(selectionChanged), name: .PDFViewSelectionChanged, object: pdfView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        pdfView.addGestureRecognizer(tap)

        // Dismiss the inline callout once the page actually scrolls (it's pinned to
        // a screen point, so it would otherwise drift off its word). Only past a
        // real threshold: PDFKit nudges contentOffset around a tap, and dismissing
        // on every change cleared the callout in the same runloop that set it.
        if let sv = Self.scrollView(in: pdfView) {
            docScrollView = sv
            scrollObs = sv.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                let offset = sv.contentOffset
                DispatchQueue.main.async { self?.dismissPopupIfScrolled(to: offset) }
            }
        }

        rebuildMatcher()
        updatePageLabel()
    }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        for sub in view.subviews {
            if let sv = sub as? UIScrollView { return sv }
            if let found = scrollView(in: sub) { return found }
        }
        return nil
    }

    /// Rebuild the matcher from the current dictionary/settings and repaint.
    func rebuildMatcher() {
        guard let app, let document else { return }
        matcher = app.matcher(documentId: document.id)
        pageMatches.removeAll()
        pageSelections.removeAll()
        refreshHighlights()
    }

    func saveProgress() {
        // Nothing is persisted until the saved view has been restored — otherwise
        // the initial page-change events would clobber the stored position.
        guard restored, let app, let document, let page = pdfView.currentPage, let doc = pdfDocument else { return }
        app.saveProgress(documentId: document.id,
                         page: doc.index(for: page) + 1,
                         viewState: captureViewState())
    }

    /// The exact current view: page + top-left visible point (page space) + zoom.
    ///
    /// Computed from the viewport ourselves — `page(for:nearest:)` + `convert(_:to:)`,
    /// the same conversions the tap hit-testing uses — NOT from `currentDestination`,
    /// whose reported point on iOS is not in the space `go(to:)` expects (restores
    /// landed about a page further on). Round-tripping the point that sits at the
    /// viewport's top-left back through `go(to:)` (which places the destination
    /// point at the top-left) is exact by construction.
    private func captureViewState() -> DocumentViewState? {
        guard let doc = pdfDocument else { return nil }
        let topLeft = CGPoint(x: pdfView.bounds.minX + 1, y: pdfView.bounds.minY + 1)
        guard let page = pdfView.page(for: topLeft, nearest: true) else { return nil }
        let p = pdfView.convert(topLeft, to: page)
        guard p.x.isFinite, p.y.isFinite else { return nil }
        return DocumentViewState(pageIndex: doc.index(for: page),
                                 x: Double(p.x), y: Double(p.y),
                                 zoom: Double(pdfView.scaleFactor))
    }

    /// Apply the saved view (sanity-checked) once layout exists; without one,
    /// fall back to the coarse last-page resume.
    private func restoreView(_ saved: DocumentViewState?, fallbackPage: Int) {
        defer { restored = true; updatePageLabel(); refreshHighlights() }
        guard let doc = pdfDocument else { return }
        if let vs = saved, vs.zoom.isFinite, vs.zoom > 0.05, vs.zoom < 20,
           let page = doc.page(at: max(0, min(vs.pageIndex, doc.pageCount - 1))) {
            pdfView.scaleFactor = CGFloat(vs.zoom)   // set zoom BEFORE the jump, or the point shifts
            pdfView.go(to: PDFDestination(page: page, at: CGPoint(x: vs.x, y: vs.y)))
        } else if let page = doc.page(at: fallbackPage) {
            pdfView.go(to: page)
        }
    }

    func clearSelection() { pdfView.clearSelection(); selection = nil }

    // MARK: Highlighting

    private func visiblePageIndices() -> [Int] {
        guard let doc = pdfDocument, let current = pdfView.currentPage else { return [] }
        let i = doc.index(for: current)
        return [i - 1, i, i + 1].filter { $0 >= 0 && $0 < doc.pageCount }
    }

    private func matches(forPage i: Int) -> [TermMatch] {
        if let cached = pageMatches[i] { return cached }
        guard let doc = pdfDocument, let page = doc.page(at: i), let text = page.string else {
            pageMatches[i] = []; return []
        }
        let m = matcher.isEmpty ? [] : matcher.findMatches(text)
        pageMatches[i] = m
        return m
    }

    private func selections(forPage i: Int) -> [PDFSelection] {
        if let cached = pageSelections[i] { return cached }
        guard let doc = pdfDocument, let page = doc.page(at: i) else { return [] }
        var sels: [PDFSelection] = []
        for match in matches(forPage: i) {
            guard let sel = page.selection(for: match.range) else { continue }
            sel.color = color(forEntry: match.entryId)
            sels.append(sel)
        }
        pageSelections[i] = sels
        return sels
    }

    private func refreshHighlights() {
        for i in visiblePageIndices() { _ = selections(forPage: i) }   // warm cache for the window
        let all = pageSelections.values.flatMap { $0 }
        pdfView.highlightedSelections = all.isEmpty ? nil : all
    }

    private func color(forEntry id: Int64) -> UIColor {
        let argb = app?.entry(id: id)?.colorValue ?? app?.settings.highlightColor ?? kDefaultHighlightColor
        return UIColor(argb: argb)
    }

    // MARK: Events

    @objc private func pageChanged() { wordPopup = nil; refreshHighlights(); updatePageLabel(); saveProgress() }

    private func updatePageLabel() {
        guard let doc = pdfDocument, let page = pdfView.currentPage else { pageLabel = ""; return }
        pageLabel = "\(doc.index(for: page) + 1) / \(doc.pageCount)"
    }

    @objc private func selectionChanged() {
        let raw = pdfView.currentSelection?.string ?? ""
        let joined = TextNormalizer.joinWrappedLines(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        selection = joined.isEmpty ? nil : joined
        if selection != nil { wordPopup = nil }   // a selection supersedes the callout
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard let doc = pdfDocument else { return }
        let loc = gr.location(in: pdfView)
        guard let page = pdfView.page(for: loc, nearest: true) else { wordPopup = nil; return }
        let pagePoint = pdfView.convert(loc, to: page)
        let idx = page.characterIndex(at: pagePoint)
        guard idx >= 0 else { wordPopup = nil; return }
        let i = doc.index(for: page)
        // Most specific (shortest) match covering the tapped character wins.
        let hit = matches(forPage: i)
            .filter { $0.start <= idx && idx < $0.end }
            .min { $0.length < $1.length }
        guard let hit else { wordPopup = nil; return }
        // The word's rect in PDFView space → anchor the callout above it.
        let rect = page.selection(for: hit.range).map { pdfView.convert($0.bounds(for: page), from: page) }
        popupAnchorOffset = docScrollView?.contentOffset ?? .zero
        wordPopup = WordPopup(entryId: hit.entryId,
                              rect: rect ?? CGRect(x: loc.x, y: loc.y, width: 1, height: 1))
    }
}

extension ReaderCoordinator: UIGestureRecognizerDelegate {
    // Let our tap coexist with PDFView's own gestures (selection, links).
    nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
