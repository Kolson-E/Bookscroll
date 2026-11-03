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
        .font(.system(.callout, design: AppSettings.shared.readerTypeface.design))
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

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
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
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        guard typeface == .serif, let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: serif, size: 0)
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
