import SwiftUI

/// What a long press on a post shows: the paragraphs around it.
struct PeekContent {
    let bookTitle: String
    let progressLine: String
    let before: [SegmentRecord]
    /// Paragraphs the post covers (one in Paragraphs style; a passage can cover several).
    let post: [SegmentRecord]
    let after: [SegmentRecord]
    let highlight: Range<Int>
}

/// Context peek: two paragraphs before the post and two after, with the post highlighted.
@MainActor
struct PeekView: View {
    let content: PeekContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(content.bookTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                Text(content.progressLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(content.before, id: \.index) { paragraph in
                Text(paragraph.text)
                    .lineLimit(4)
                    .foregroundStyle(Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(content.post, id: \.index) { paragraph in
                    Text(paragraph.text)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            .padding(10)
            .background(Theme.highlight, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) {
                Theme.accent.frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
            ForEach(content.after, id: \.index) { paragraph in
                Text(paragraph.text)
                    .lineLimit(4)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .font(AppSettings.shared.readerTypeface.font(.callout))
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(Theme.background)
    }
}

/// A UITextView that shows text read-only but lets the reader select words. The system menu
/// then offers Look Up (dictionary), Copy, Translate and Share.
@MainActor
struct SelectableText: UIViewRepresentable {
    let text: String
    var font: UIFont
    var color: UIColor
    var lineSpacing: CGFloat = 3
    /// UTF-16 range to give a background colour (part of a paragraph highlighted).
    var highlight: NSRange?
    var highlightColor: UIColor = .clear
    /// Bookmark colours (UTF-16 ranges of `text`), drawn over `highlight` and under `marks`.
    var tints: [(range: NSRange, color: UIColor)] = []
    /// The reader's own highlights (UTF-16 ranges of `text`), drawn over `highlight`.
    var marks: [NSRange] = []
    var markColor: UIColor = .clear
    /// When set, the edit menu of a selection offers Highlight (or Remove highlight when the
    /// selection touches a highlight).
    var onHighlight: ((NSRange) -> Void)?
    var onRemoveHighlight: ((NSRange) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectableText

        init(parent: SelectableText) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let onHighlight = parent.onHighlight else { return nil }
            let touchesMark = parent.marks.contains { NSIntersectionRange($0, range).length > 0 }
            let action: UIAction
            if touchesMark, let onRemove = parent.onRemoveHighlight {
                action = UIAction(title: "Remove highlight", image: UIImage(systemName: "highlighter")) { _ in
                    textView.selectedRange = NSRange(location: range.location, length: 0)
                    onRemove(range)
                }
            } else {
                action = UIAction(title: "Highlight", image: UIImage(systemName: "highlighter")) { _ in
                    textView.selectedRange = NSRange(location: range.location, length: 0)
                    onHighlight(range)
                }
            }
            return UIMenu(children: [action as UIMenuElement] + suggestedActions)
        }
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.dataDetectorTypes = []
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ])
        if let highlight, highlight.location >= 0, NSMaxRange(highlight) <= attributed.length {
            attributed.addAttribute(.backgroundColor, value: highlightColor, range: highlight)
        }
        for tint in tints where tint.range.location >= 0 && NSMaxRange(tint.range) <= attributed.length {
            attributed.addAttribute(.backgroundColor, value: tint.color, range: tint.range)
        }
        for mark in marks where mark.location >= 0 && NSMaxRange(mark) <= attributed.length {
            attributed.addAttribute(.backgroundColor, value: markColor, range: mark)
        }
        if view.attributedText != attributed {
            view.attributedText = attributed
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    /// The body font in the reader's typeface, following Dynamic Type.
    static func readerFont(_ typeface: Typeface, textStyle: UIFont.TextStyle = .body) -> UIFont {
        typeface.uiFont(textStyle: textStyle)
    }
}

/// "Look up a word": the post text, selectable, so the system Look Up works on any word.
@MainActor
struct LookUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let post: FeedPost

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Touch and hold a word, then choose Look Up.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    SelectableText(
                        text: post.segment.text,
                        font: SelectableText.readerFont(AppSettings.shared.readerTypeface),
                        color: UIColor(Theme.primaryText)
                    )
                    .id(dynamicTypeSize)
                    .accessibilityIdentifier("lookup.text")
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(post.bookTitle)
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }
}
