import Observation
import SwiftUI

/// Continuous reader around a post: paragraphs in book layout, loaded in both directions.
@MainActor
@Observable
final class ContextReaderModel {
    static let window = 25

    let book: FeedBook
    let highlight: Range<Int>
    private(set) var paragraphs: [SegmentRecord] = []
    private(set) var anchorIndex = 0
    private(set) var canLoadEarlier = false
    private(set) var canLoadLater = false
    /// Top visible paragraph, bound to the scroll view.
    var topVisibleIndex: Int?

    private let store: LibraryStore

    init(store: LibraryStore, book: FeedBook, charStart: Int, charEnd: Int) {
        self.store = store
        self.book = book
        self.highlight = charStart..<max(charStart + 1, charEnd)
        let anchor = store.indexContaining(offset: charStart, book: book, style: .paragraph) ?? 0
        anchorIndex = anchor
        let before = store.segments(book: book, style: .paragraph, before: anchor, limit: Self.window)
        let after = store.segments(book: book, style: .paragraph, from: anchor, limit: Self.window + 1)
        paragraphs = before + after
        updateFlags()
    }

    func loadEarlier() {
        guard canLoadEarlier, let first = paragraphs.first else { return }
        let earlier = store.segments(book: book, style: .paragraph, before: first.index, limit: Self.window)
        paragraphs.insert(contentsOf: earlier, at: 0)
        updateFlags()
    }

    func loadLater() {
        guard canLoadLater, let last = paragraphs.last else { return }
        let later = store.segments(book: book, style: .paragraph, from: last.index + 1, limit: Self.window)
        paragraphs.append(contentsOf: later)
        updateFlags()
    }

    /// Offset of the top visible paragraph, used by "Continue in feed from here".
    var continueOffset: Int {
        let index = topVisibleIndex ?? anchorIndex
        return paragraphs.first { $0.index == index }?.charStart ?? highlight.lowerBound
    }

    func isHighlighted(_ paragraph: SegmentRecord) -> Bool {
        paragraph.charStart < highlight.upperBound && highlight.lowerBound < paragraph.charEnd
    }

    /// Shows a chapter heading where the chapter changes.
    func chapterHeading(before position: Int) -> String? {
        let paragraph = paragraphs[position]
        guard !paragraph.chapter.isEmpty else { return nil }
        if position == 0 { return paragraph.chapter }
        return paragraphs[position - 1].chapter == paragraph.chapter ? nil : paragraph.chapter
    }

    private func updateFlags() {
        canLoadEarlier = (paragraphs.first?.index ?? 0) > 0
        canLoadLater = (paragraphs.last?.index ?? 0) < book.paragraphCount - 1
    }
}

@MainActor
struct ContextReaderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: ContextReaderModel
    @State private var ready = false
    @State private var showsJump = false

    init(model: ContextReaderModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(model.paragraphs.enumerated()), id: \.element.index) { position, paragraph in
                            VStack(alignment: .leading, spacing: 8) {
                                if let heading = model.chapterHeading(before: position) {
                                    Text(heading)
                                        .font(AppSettings.shared.readerTypeface.font(.title3, bold: true))
                                        .foregroundStyle(Theme.primaryText)
                                        .padding(.top, 12)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                ReaderParagraph(
                                    paragraph: paragraph,
                                    highlight: model.highlight,
                                    isHighlighted: model.isHighlighted(paragraph),
                                    marks: app.marks.highlightRanges(bookID: model.book.id, start: paragraph.charStart, end: paragraph.textEnd),
                                    bookmarkMarks: app.marks.bookmarkHighlights(bookID: model.book.id, start: paragraph.charStart, end: paragraph.textEnd),
                                    onHighlight: { range in
                                        _ = app.marks.addHighlight(bookID: model.book.id, start: paragraph.charStart + range.location, end: paragraph.charStart + NSMaxRange(range))
                                    },
                                    onRemoveHighlight: { range in
                                        app.marks.removeHighlights(bookID: model.book.id, start: paragraph.charStart + range.location, end: paragraph.charStart + NSMaxRange(range))
                                    }
                                )
                                let images = BookImageCache.shared.images(bookID: model.book.id, start: paragraph.charStart, end: paragraph.charEnd)
                                if !images.isEmpty {
                                    PostImages(bookID: model.book.id, images: images)
                                        .padding(.top, 4)
                                }
                            }
                            .id(paragraph.index)
                            .onAppear { paragraphAppeared(paragraph, proxy: proxy) }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollPosition(id: $model.topVisibleIndex)
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(model.anchorIndex, anchor: .center)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ready = true }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(model.book.title)
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsJump = true
                    } label: {
                        Label("Jump to", systemImage: "list.bullet.indent")
                    }
                    .accessibilityHint("Chapters and percent")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsJump) {
                JumpSheet(bookID: model.book.id)
                    .environment(app)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    app.continueInFeed(bookID: model.book.id, offset: model.continueOffset)
                } label: {
                    // White on the dark accent in light mode, black on the light accent in dark mode.
                    Label("Continue in feed from here", systemImage: "arrow.down.forward.circle")
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityHint("Sets your place in this book to the top paragraph on screen")
            }
        }
        .tint(Theme.accent)
    }

    private func paragraphAppeared(_ paragraph: SegmentRecord, proxy: ScrollViewProxy) {
        guard ready else { return }
        if paragraph.index == model.paragraphs.first?.index, model.canLoadEarlier {
            let previousFirst = paragraph.index
            model.loadEarlier()
            DispatchQueue.main.async {
                proxy.scrollTo(previousFirst, anchor: .top)
            }
        } else if paragraph.index == model.paragraphs.last?.index, model.canLoadLater {
            model.loadLater()
        }
    }
}

@MainActor
private struct ReaderParagraph: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let paragraph: SegmentRecord
    let highlight: Range<Int>
    let isHighlighted: Bool
    /// The reader's highlights in this paragraph (UTF-16 ranges of its text).
    let marks: [NSRange]
    /// Coloured bookmarks in this paragraph (UTF-16 ranges of its text).
    var bookmarkMarks: [MarkerRange] = []
    let onHighlight: (NSRange) -> Void
    let onRemoveHighlight: (NSRange) -> Void

    private var wholeParagraph: NSRange { NSRange(location: 0, length: (paragraph.text as NSString).length) }

    /// The post covers the whole paragraph (always true in Paragraphs style).
    private var coversParagraph: Bool {
        let length = (paragraph.text as NSString).length
        return highlight.lowerBound <= paragraph.charStart && highlight.upperBound >= paragraph.charStart + length
    }

    var body: some View {
        SelectableText(
            text: paragraph.text,
            font: SelectableText.readerFont(AppSettings.shared.readerTypeface),
            color: UIColor(Theme.primaryText),
            highlight: partialHighlight,
            highlightColor: UIColor(Theme.highlight),
            tints: bookmarkMarks.compactMap { marker in
                Theme.bookmarkHighlight(marker.color).map { (range: marker.range, color: UIColor($0)) }
            },
            marks: marks,
            markColor: UIColor(Theme.marker),
            onHighlight: onHighlight,
            onRemoveHighlight: onRemoveHighlight
        )
            .id(dynamicTypeSize)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isHighlighted ? 12 : 0)
            .padding(.trailing, isHighlighted && coversParagraph ? 8 : 0)
            .padding(.vertical, isHighlighted && coversParagraph ? 6 : 0)
            // A whole highlighted paragraph gets one solid block; part of a paragraph is
            // highlighted inside the text.
            .background(alignment: .leading) {
                if isHighlighted && coversParagraph {
                    Theme.highlight
                }
            }
            .overlay(alignment: .leading) {
                if isHighlighted {
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 3)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            // VoiceOver cannot select inside the paragraph, so it highlights the whole paragraph.
            .accessibilityAction(named: marks.isEmpty ? "Highlight paragraph" : "Remove highlight") {
                if marks.isEmpty { onHighlight(wholeParagraph) } else { onRemoveHighlight(wholeParagraph) }
            }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if isHighlighted { parts.append("Selected post.") }
        if !marks.isEmpty { parts.append(marks.count == 1 ? "Contains a highlight." : "Contains \(marks.count) highlights.") }
        parts.append(paragraph.text)
        return parts.joined(separator: " ")
    }

    /// The highlighted part of the paragraph, relative to its text; nil when none or all of it.
    private var partialHighlight: NSRange? {
        guard isHighlighted, !coversParagraph else { return nil }
        let length = (paragraph.text as NSString).length
        let lower = max(highlight.lowerBound, paragraph.charStart) - paragraph.charStart
        let upper = min(highlight.upperBound, paragraph.charStart + length) - paragraph.charStart
        guard lower < upper else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

}
