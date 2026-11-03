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

struct ContextReaderView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: ContextReaderModel
    @State private var ready = false

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
                                        .font(.system(.title3, design: .serif).weight(.semibold))
                                        .padding(.top, 12)
                                        .accessibilityAddTraits(.isHeader)
                                }
                                ReaderParagraph(
                                    paragraph: paragraph,
                                    highlight: model.highlight,
                                    isHighlighted: model.isHighlighted(paragraph)
                                )
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    app.continueInFeed(bookID: model.book.id, offset: model.continueOffset)
                } label: {
                    Label("Continue in feed from here", systemImage: "arrow.down.forward.circle")
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

private struct ReaderParagraph: View {
    let paragraph: SegmentRecord
    let highlight: Range<Int>
    let isHighlighted: Bool

    var body: some View {
        Text(attributed)
            .font(.system(.body, design: .serif))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, isHighlighted ? 10 : 0)
            .overlay(alignment: .leading) {
                if isHighlighted {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isHighlighted ? "Selected post. \(paragraph.text)" : paragraph.text)
    }

    private var attributed: AttributedString {
        var text = AttributedString(paragraph.text)
        guard isHighlighted else { return text }
        let length = (paragraph.text as NSString).length
        let lower = max(highlight.lowerBound, paragraph.charStart) - paragraph.charStart
        let upper = min(highlight.upperBound, paragraph.charStart + length) - paragraph.charStart
        guard lower < upper,
              let range = Range(NSRange(location: lower, length: upper - lower), in: text) else { return text }
        text[range][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Color.accentColor.opacity(0.18)
        return text
    }
}
