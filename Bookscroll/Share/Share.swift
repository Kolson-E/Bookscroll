import SwiftUI
import UIKit

enum ShareFormatter {
    /// The post text in quotes, followed by "Title by Author".
    static func quote(text: String, title: String, author: String) -> String {
        "\u{201C}\(text)\u{201D}\n\n\(title) by \(author)"
    }

    static func quote(_ post: FeedPost) -> String {
        quote(text: post.segment.text, title: post.bookTitle, author: post.bookAuthor)
    }

    /// The post text in quotes, then "— Title, Author · Chapter · 42%". The chapter is left
    /// out when the book has no chapter labels.
    static func citation(text: String, title: String, author: String, chapter: String, percent: Int) -> String {
        var source = "\u{2014} \(title), \(author)"
        if !chapter.isEmpty { source += " \u{00B7} \(chapter)" }
        source += " \u{00B7} \(percent)%"
        return "\u{201C}\(text)\u{201D}\n\(source)"
    }

    static func citation(_ post: FeedPost) -> String {
        citation(text: post.segment.text, title: post.bookTitle, author: post.bookAuthor, chapter: post.segment.chapter, percent: post.percent)
    }
}

/// Looks of the share card.
enum ShareCardStyle: String, CaseIterable, Identifiable {
    /// Like a post: avatar, title and author, then the text.
    case post
    /// A large quote with the source under it.
    case quote
    /// Only the text and a one-line source.
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .post: return "Post"
        case .quote: return "Quote"
        case .minimal: return "Minimal"
        }
    }
}

/// Colours of the share card, independent of the app theme.
enum ShareCardTheme: String, CaseIterable, Identifiable {
    case light
    case dark
    case sepia

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .sepia: return "Sepia"
        }
    }

    var background: Color {
        switch self {
        case .light: return Color(uiColor: UIColor(hex: PaletteHex.lightBackground))
        case .dark: return Color(uiColor: UIColor(hex: PaletteHex.darkBackground))
        case .sepia: return Color(uiColor: UIColor(hex: PaletteHex.sepiaBackground))
        }
    }

    var primary: Color {
        switch self {
        case .light: return Color(uiColor: UIColor(hex: PaletteHex.lightPrimary))
        case .dark: return Color(uiColor: UIColor(hex: PaletteHex.darkPrimary))
        case .sepia: return Color(uiColor: UIColor(hex: PaletteHex.sepiaPrimary))
        }
    }

    var secondary: Color {
        switch self {
        case .light: return Color(uiColor: UIColor(hex: PaletteHex.lightSecondary))
        case .dark: return Color(uiColor: UIColor(hex: PaletteHex.darkSecondary))
        case .sepia: return Color(uiColor: UIColor(hex: PaletteHex.sepiaSecondary))
        }
    }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// What a share card shows. Built from a post or from a highlight.
struct ShareCardContent: Equatable {
    let text: String
    let title: String
    let author: String
    let chapter: String
    let percent: Int

    init(text: String, title: String, author: String, chapter: String, percent: Int) {
        self.text = text
        self.title = title
        self.author = author
        self.chapter = chapter
        self.percent = percent
    }

    init(_ post: FeedPost) {
        self.init(text: post.segment.text, title: post.bookTitle, author: post.bookAuthor, chapter: post.segment.chapter, percent: post.percent)
    }

    /// "Title, Author · Chapter".
    var source: String {
        var line = "\(title), \(author)"
        if !chapter.isEmpty { line += " \u{00B7} \(chapter)" }
        return line
    }
}

/// The share card image. A fixed width and text size, so the image is the same on every device.
@MainActor
struct ShareCardView: View {
    let content: ShareCardContent
    var style: ShareCardStyle = .post
    var theme: ShareCardTheme = .light
    var accent: Color = AccentChoice.blue.color

    /// Long texts are cut so the image stays a sensible size.
    static let lineLimit = 24

    var body: some View {
        Group {
            switch style {
            case .post: postCard
            case .quote: quoteCard
            case .minimal: minimalCard
            }
        }
        .frame(width: 390, alignment: .leading)
        .background(theme.background)
        .environment(\.colorScheme, theme.colorScheme)
        .environment(\.dynamicTypeSize, .large)
    }

    private var postCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(title: content.title, author: content.author, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.headline)
                        .foregroundStyle(theme.primary)
                    Text(content.author)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondary)
                }
            }
            Text(content.text)
                .font(.system(size: 19))
                .foregroundStyle(theme.primary)
                .lineLimit(Self.lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            Text(content.chapter.isEmpty ? "\(content.percent)%" : "\(content.chapter) \u{00B7} \(content.percent)%")
                .font(.footnote)
                .foregroundStyle(theme.secondary)
        }
        .padding(28)
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\u{201C}")
                .font(.system(size: 72, weight: .bold, design: .serif))
                .foregroundStyle(accent)
                .frame(height: 44, alignment: .top)
                .accessibilityHidden(true)
            Text(content.text)
                .font(.system(size: 24, design: .serif))
                .foregroundStyle(theme.primary)
                .lineSpacing(4)
                .lineLimit(Self.lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                accent.frame(width: 28, height: 3)
                Text(content.source)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(36)
    }

    private var minimalCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.text)
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(theme.primary)
                .lineSpacing(3)
                .lineLimit(Self.lineLimit)
                .fixedSize(horizontal: false, vertical: true)
            Text("\u{2014} \(content.source)")
                .font(.footnote)
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(28)
    }
}

@MainActor
enum ShareCardRenderer {
    static func image(for content: ShareCardContent, style: ShareCardStyle, theme: ShareCardTheme, accent: Color) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(content: content, style: style, theme: theme, accent: accent))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Share as image: a preview of the card, its style and colours, and the share button.
@MainActor
struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let content: ShareCardContent
    @AppStorage("shareCardStyle") private var style: ShareCardStyle = .post
    @AppStorage("shareCardTheme") private var cardTheme: ShareCardTheme = .light
    @State private var image: UIImage?

    private var renderKey: String { "\(style.rawValue)|\(cardTheme.rawValue)|\(AppSettings.shared.accent.rawValue)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("Style", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("share.style")
                    Picker("Colours", selection: $cardTheme) {
                        ForEach(ShareCardTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("share.theme")
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.separator, lineWidth: 1))
                            .accessibilityLabel("Card preview: \(content.text)")
                            .accessibilityIdentifier("share.preview")
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview(content.title, image: Image(uiImage: image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .foregroundStyle(Theme.background)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("share.send")
                    } else {
                        ProgressView()
                    }
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle("Share as image")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .task(id: renderKey) {
            image = ShareCardRenderer.image(for: content, style: style, theme: cardTheme, accent: AppSettings.shared.accent.color)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
