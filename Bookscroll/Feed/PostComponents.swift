import SwiftUI
import UIKit

/// sRGB values of the theme colours that carry text. `PaletteTests` checks their contrast.
enum PaletteHex {
    static let lightBackground: UInt32 = 0xFFFFFF
    static let lightSecondaryBackground: UInt32 = 0xF7F9F9
    static let lightPrimary: UInt32 = 0x0F1419
    /// X's light grey.
    static let lightSecondary: UInt32 = 0x536471
    static let lightHighlight: UInt32 = 0xFDE8D9
    /// Background of the reader's own highlights (a marker pen).
    static let lightMarker: UInt32 = 0xFFF0A8

    static let darkBackground: UInt32 = 0x000000
    static let darkSecondaryBackground: UInt32 = 0x16181C
    static let darkPrimary: UInt32 = 0xE7E9EA
    /// A little lighter than X's dark grey (0x71767B, 4.6:1), for margin.
    static let darkSecondary: UInt32 = 0x7E858B
    static let darkHighlight: UInt32 = 0x452912
    static let darkMarker: UInt32 = 0x4A3D00

    static let sepiaBackground: UInt32 = 0xF8F0E0
    static let sepiaSecondaryBackground: UInt32 = 0xF1E6CF
    static let sepiaPrimary: UInt32 = 0x3D2E1F
    static let sepiaSecondary: UInt32 = 0x6B5A45
    static let sepiaHighlight: UInt32 = 0xEEDCB8
    static let sepiaMarker: UInt32 = 0xF0D98A

    /// WCAG 2 contrast ratio of two sRGB colours.
    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            func channel(_ shift: UInt32) -> Double {
                let value = Double((hex >> shift) & 0xFF) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

/// Colours of the current theme. Night, Light and System use the system light and dark
/// colours (the theme forces the colour scheme); Sepia has its own palette. Every text colour
/// reaches 4.5:1 on its background. Reading `AppSettings.shared` inside a view body makes the
/// view update when the theme changes.
@MainActor
enum Theme {
    private static var isSepia: Bool { AppSettings.shared.theme == .sepia }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static let systemBackground = adaptive(light: PaletteHex.lightBackground, dark: PaletteHex.darkBackground)
    private static let systemSecondaryBackground = adaptive(light: PaletteHex.lightSecondaryBackground, dark: PaletteHex.darkSecondaryBackground)
    private static let systemPrimary = adaptive(light: PaletteHex.lightPrimary, dark: PaletteHex.darkPrimary)
    private static let systemSecondary = adaptive(light: PaletteHex.lightSecondary, dark: PaletteHex.darkSecondary)
    private static let systemSeparator = adaptive(light: 0xEFF3F4, dark: 0x2F3336)
    private static let systemThreadLine = adaptive(light: 0xCFD9DE, dark: 0x333639)
    private static let systemHighlight = adaptive(light: PaletteHex.lightHighlight, dark: PaletteHex.darkHighlight)
    private static let systemMarker = adaptive(light: PaletteHex.lightMarker, dark: PaletteHex.darkMarker)

    private static let sepiaBackground = Color(uiColor: UIColor(hex: PaletteHex.sepiaBackground))
    private static let sepiaSecondaryBackground = Color(uiColor: UIColor(hex: PaletteHex.sepiaSecondaryBackground))
    private static let sepiaPrimary = Color(uiColor: UIColor(hex: PaletteHex.sepiaPrimary))
    private static let sepiaSecondary = Color(uiColor: UIColor(hex: PaletteHex.sepiaSecondary))
    private static let sepiaSeparator = Color(uiColor: UIColor(hex: 0xE3D5BC))
    private static let sepiaThreadLine = Color(uiColor: UIColor(hex: 0xD9C9AC))
    private static let sepiaHighlight = Color(uiColor: UIColor(hex: PaletteHex.sepiaHighlight))
    private static let sepiaMarker = Color(uiColor: UIColor(hex: PaletteHex.sepiaMarker))

    /// White, pure black, or sepia paper.
    static var background: Color { isSepia ? sepiaBackground : systemBackground }
    /// Grouped rows (Settings) and cards.
    static var secondaryBackground: Color { isSepia ? sepiaSecondaryBackground : systemSecondaryBackground }
    static var primaryText: Color { isSepia ? sepiaPrimary : systemPrimary }
    static var secondaryText: Color { isSepia ? sepiaSecondary : systemSecondary }
    static var separator: Color { isSepia ? sepiaSeparator : systemSeparator }
    static var threadLine: Color { isSepia ? sepiaThreadLine : systemThreadLine }
    /// Background of the tapped post in the reader. Opaque, so text on it keeps full contrast.
    static var highlight: Color { isSepia ? sepiaHighlight : systemHighlight }
    /// Background of the reader's own highlights. Opaque; primary text keeps 8.8:1 or more.
    static var marker: Color { isSepia ? sepiaMarker : systemMarker }
    static var accent: Color { AppSettings.shared.accent.color }
    /// X's like colour.
    static let like = adaptive(light: 0xC2135F, dark: 0xF91880)
}

@MainActor
extension View {
    /// Solid navigation bar in the theme's background colour (the default material looks
    /// grey on sepia).
    func themedNavigationBar() -> some View {
        toolbarBackground(Theme.background, for: .navigationBar)
    }
}

/// A one-point line in the theme's separator colour (X uses hairlines between posts).
@MainActor
struct ThemedDivider: View {
    var body: some View {
        Theme.separator
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Stable colour per book (FNV-1a hash of title and author; Swift's hashValue is randomized per launch).
enum BookColor {
    static func hue(for seed: String) -> Double {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return Double(hash % 360) / 360
    }

    /// Dark enough for white text at 4.5:1 or more for every hue (yellow is the worst case).
    static func color(title: String, author: String) -> Color {
        Color(hue: hue(for: title + "|" + author), saturation: 0.6, brightness: 0.45)
    }
}

@MainActor
struct AvatarView: View {
    let title: String
    let author: String
    let size: CGFloat
    /// The letter follows Dynamic Type through this style; `size` should be a @ScaledMetric.
    var textStyle: Font.TextStyle = .title2
    /// The book, to show its cover or the reader's photo. Nil shows the initial.
    var bookID: UUID? = nil
    /// An image to show instead of looking one up (share cards render off screen).
    var image: UIImage? = nil

    private var shownImage: UIImage? {
        if let image { return image }
        guard let bookID else { return nil }
        return CoverCache.shared.image(for: bookID)
    }

    var body: some View {
        if let shownImage {
            // A cover is taller than wide; the circle shows its top centre, where titles are.
            Image(uiImage: shownImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size, alignment: .top)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.separator, lineWidth: 0.5))
        } else {
            Circle()
                .fill(BookColor.color(title: title, author: author))
                .frame(width: size, height: size)
                .overlay {
                    Text(initial)
                        .font(.system(textStyle, design: .serif).weight(.bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(size * 0.12)
                }
        }
    }

    private var initial: String {
        if let first = title.first(where: { $0.isLetter || $0.isNumber }) {
            return String(first).uppercased()
        }
        return "?"
    }
}

/// Chapter row above a thread in One book mode. At the start of a chapter it says so in the
/// accent colour.
@MainActor
struct ChapterHeaderRow: View {
    let title: String
    var isStart = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isStart ? "book.pages" : "text.book.closed")
                .imageScale(.small)
            Text(isStart ? "New chapter \u{00B7} \(title)" : title)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(isStart ? Theme.accent : Theme.secondaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isStart ? "Chapter: \(title). New chapter begins." : "Chapter: \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a post can do. Built by `AppModel.actions(for:)`.
struct PostActions {
    /// The book's current Mix weight, to tick the right menu item.
    var bookFeedWeight: Double = 1
    var like: () -> Void
    var bookmark: () -> Void
    var open: () -> Void
    var shareText: () -> Void
    var shareImage: () -> Void
    var copy: (_ withCitation: Bool) -> Void
    var hideFromMix: () -> Void = {}
    var snooze: (_ days: Int) -> Void = { _ in }
    var setWeight: (_ weight: Double) -> Void = { _ in }
    var peek: () -> PeekContent? = { nil }
    var lookUp: () -> Void = {}
    var continueHere: () -> Void = {}
    /// Highlights the whole post, or removes the highlights in it.
    var highlight: () -> Void = {}
}

/// Single tap opens the reader. With double-tap to like on, a double tap likes the post and
/// the single tap waits for the double tap to fail (as in X).
@MainActor
private struct PostTapGestures: ViewModifier {
    let doubleTapEnabled: Bool
    let onSingle: () -> Void
    let onDouble: () -> Void

    func body(content: Content) -> some View {
        if doubleTapEnabled {
            content
                .onTapGesture(count: 2, perform: onDouble)
                .onTapGesture(perform: onSingle)
        } else {
            content.onTapGesture(perform: onSingle)
        }
    }
}

/// One timeline post in X's layout: avatar, bold title with the author in grey, chapter and
/// progress, the text, and a grey action bar. Focus mode shows the text only.
@MainActor
struct PostRow: View {
    let post: FeedPost
    let isLiked: Bool
    let isBookmarked: Bool
    /// The reader's highlights inside this post, as UTF-16 ranges of the post text.
    var highlights: [NSRange] = []
    let actions: PostActions

    @State private var expanded = false
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var heartBurst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var comfortableAvatar: CGFloat = 40
    @ScaledMetric(relativeTo: .body) private var compactAvatar: CGFloat = 32

    private var settings: AppSettings { AppSettings.shared }
    private var isCompact: Bool { settings.density == .compact }
    private var focusMode: Bool { settings.focusMode }
    /// Grows with Dynamic Type but stops at 56 pt, so large text keeps a wide text column.
    private var avatarSize: CGFloat { min(isCompact ? compactAvatar : comfortableAvatar, 56) }
    private var horizontalPadding: CGFloat { isCompact ? 12 : 16 }
    private var topPadding: CGFloat { isCompact ? 8 : 12 }
    private static let collapsedLineLimit = 10

    private var isTruncated: Bool { !expanded && fullHeight > limitedHeight + 1 }

    private var textFont: Font {
        switch settings.postTypeface {
        case .sans: return .callout
        case .serif: return .system(.body, design: .serif)
        }
    }

    private var textLineSpacing: CGFloat { settings.postTypeface == .sans ? 3 : 2 }

    var body: some View {
        VStack(spacing: 0) {
            if let header = post.chapterHeader {
                ChapterHeaderRow(title: header, isStart: post.startsChapter)
                ThemedDivider()
            }
            content
                .overlay(alignment: .topLeading) {
                    if !focusMode { threadLines }
                }
            if !post.threadContinuesBelow || focusMode {
                ThemedDivider()
            }
        }
        .background(Theme.background)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: isCompact ? 8 : 12) {
            if !focusMode {
                Button(action: actions.open) {
                    AvatarView(title: post.bookTitle, author: post.bookAuthor, size: avatarSize, textStyle: .title3, bookID: post.bookID)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read \(post.bookTitle) in context")
            }

            VStack(alignment: .leading, spacing: 2) {
                textGroup
                    .overlay(alignment: .topTrailing) {
                        if !focusMode { moreMenu }
                    }
                if isTruncated || (post.showsThreadButton && !focusMode) {
                    HStack(spacing: 20) {
                        if isTruncated {
                            Button("Show more") { expanded = true }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityHint("Shows the whole post")
                                .accessibilityIdentifier("post.showMore")
                        }
                        if post.showsThreadButton && !focusMode {
                            Button("Show thread", action: actions.open)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityHint("Opens the book around this post")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.borderless)
                }
                if !focusMode {
                    actionRow
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, focusMode ? topPadding + 6 : topPadding)
        .padding(.bottom, focusMode ? topPadding + 6 : (isCompact ? 0 : 2))
    }

    private var textGroup: some View {
        VStack(alignment: .leading, spacing: isCompact ? 1 : 2) {
            if showsChapterStartLine {
                Label("New chapter \u{00B7} \(post.segment.chapter)", systemImage: "book.pages")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, focusMode ? 0 : 36)
                    .padding(.bottom, 2)
            }
            if !focusMode {
                // Title and author share a line when they fit, otherwise they stack. Nothing is cut off.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        titleText
                        authorText
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        titleText
                        authorText
                    }
                }
                .padding(.trailing, showsChapterStartLine ? 0 : 36)
                Text(post.progressLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            postText
                .padding(.top, focusMode ? 0 : 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(PostTapGestures(doubleTapEnabled: settings.doubleTapToLike, onSingle: actions.open, onDouble: doubleTapLike))
        .overlay {
            if heartBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.like)
                    .shadow(color: .black.opacity(0.25), radius: 6)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            contextMenuItems
        } preview: {
            if let content = actions.peek() {
                PeekView(content: content)
            } else {
                PeekView(content: PeekContent(bookTitle: post.bookTitle, progressLine: post.progressLine, before: [], post: [post.segment], after: [], highlight: post.segment.charStart..<post.segment.charEnd))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to read in context")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, actions.open)
        .accessibilityAction(named: isLiked ? "Unlike" : "Like", actions.like)
        .accessibilityAction(named: isBookmarked ? "Remove bookmark" : "Bookmark", actions.bookmark)
        .accessibilityAction(named: highlights.isEmpty ? "Highlight" : "Remove highlight", actions.highlight)
        .accessibilityAction(named: "Copy with citation") { actions.copy(true) }
        .accessibilityIdentifier("post")
    }

    /// Long-press menu under the context peek.
    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: actions.like) {
            Label(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.slash" : "heart")
        }
        Button(action: actions.bookmark) {
            Label(isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
        }
        Button(action: actions.highlight) {
            Label(highlights.isEmpty ? "Highlight" : "Remove highlight", systemImage: "highlighter")
        }
        Button { actions.copy(true) } label: {
            Label("Copy with citation", systemImage: "quote.bubble")
        }
        Button(action: actions.lookUp) {
            Label("Look up a word", systemImage: "character.book.closed")
        }
        Divider()
        Button(action: actions.open) {
            Label("Read in context", systemImage: "book")
        }
        Button(action: actions.continueHere) {
            Label("Continue from here", systemImage: "arrow.down.forward.circle")
        }
    }

    /// The chapter-start line inside the post. One book mode shows it in the chapter row instead.
    private var showsChapterStartLine: Bool {
        post.startsChapter && post.chapterHeader == nil
    }

    /// X's "⋯" menu: feed controls for this post's book.
    private var moreMenu: some View {
        Menu {
            Section(post.bookTitle) {
                Button { actions.setWeight(2) } label: {
                    Label("Show more from this book", systemImage: actions.bookFeedWeight > 1 ? "checkmark" : "plus.circle")
                }
                Button { actions.setWeight(1) } label: {
                    Label("Normal amount", systemImage: actions.bookFeedWeight == 1 ? "checkmark" : "equal.circle")
                }
                Button { actions.setWeight(0.5) } label: {
                    Label("Show less from this book", systemImage: actions.bookFeedWeight < 1 ? "checkmark" : "minus.circle")
                }
            }
            Section {
                Button { actions.snooze(1) } label: {
                    Label("Snooze book for a day", systemImage: "moon.zzz")
                }
                Button { actions.snooze(7) } label: {
                    Label("Snooze book for a week", systemImage: "moon.zzz")
                }
                Button(role: .destructive, action: actions.hideFromMix) {
                    Label("Hide book from Mix", systemImage: "eye.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .offset(x: 12, y: -12)
        .accessibilityLabel("More options for \(post.bookTitle)")
        .accessibilityIdentifier("post.more")
    }

    /// Double tap only likes (never unlikes), like X and Instagram, and shows a heart.
    private func doubleTapLike() {
        if !isLiked { actions.like() }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { heartBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { heartBurst = false }
        }
    }

    private var titleText: some View {
        Text(post.bookTitle)
            .font(.callout.weight(.bold))
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var authorText: some View {
        Text(post.bookAuthor)
            .font(.callout)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The post text with the reader's highlights marked.
    private var markedText: AttributedString {
        var text = AttributedString(post.segment.text)
        for range in highlights {
            guard let bounds = Range(range, in: text) else { continue }
            text[bounds][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Theme.marker
        }
        return text
    }

    private var postText: some View {
        Text(markedText)
            .font(textFont)
            .lineSpacing(textLineSpacing)
            .foregroundStyle(Theme.primaryText)
            .lineLimit(expanded ? nil : Self.collapsedLineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { limitedHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in limitedHeight = height }
                }
            )
            .background(alignment: .topLeading) {
                if !expanded {
                    Text(post.segment.text)
                        .font(textFont)
                        .lineSpacing(textLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hidden()
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { fullHeight = proxy.size.height }
                                    .onChange(of: proxy.size.height) { _, height in fullHeight = height }
                            }
                        )
                        .accessibilityHidden(true)
                }
            }
    }

    private var actionRow: some View {
        HStack {
            Button(action: actions.like) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? Theme.like : Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isLiked ? "Unlike" : "Like")
            .accessibilityValue(isLiked ? "Liked" : "Not liked")
            Spacer(minLength: 0)
            Button(action: actions.bookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? Theme.accent : Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark")
            .accessibilityValue(isBookmarked ? "Bookmarked" : "Not bookmarked")
            Spacer(minLength: 0)
            Button(action: actions.open) {
                Image(systemName: "book")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Read in context")
            Spacer(minLength: 0)
            Menu {
                Button { actions.copy(false) } label: {
                    Label("Copy text", systemImage: "doc.on.doc")
                }
                Button { actions.copy(true) } label: {
                    Label("Copy with citation", systemImage: "quote.bubble")
                }
                Divider()
                Button(action: actions.shareText) {
                    Label("Share as text", systemImage: "text.quote")
                }
                Button(action: actions.shareImage) {
                    Label("Share as image", systemImage: "photo")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share")
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
    }

    /// Thin vertical line through the avatar column that joins the posts of a thread.
    private var threadLines: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.threadLine)
                .frame(width: 2, height: max(0, topPadding - 2))
                .opacity(post.continuesThread ? 1 : 0)
            Color.clear
                .frame(width: 2, height: avatarSize + 4)
            Rectangle()
                .fill(Theme.threadLine)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .opacity(post.threadContinuesBelow ? 1 : 0)
        }
        .padding(.leading, horizontalPadding + avatarSize / 2 - 1)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if post.continuesThread { parts.append("Continues thread.") }
        if showsChapterStartLine { parts.append("New chapter: \(post.segment.chapter).") }
        parts.append("\(post.bookTitle), by \(post.bookAuthor).")
        if !post.segment.chapter.isEmpty { parts.append("\(post.segment.chapter).") }
        parts.append("\(post.percent) percent.")
        if post.partCount > 1 { parts.append("Part \(post.part) of \(post.partCount).") }
        if isLiked { parts.append("Liked.") }
        if isBookmarked { parts.append("Bookmarked.") }
        if !highlights.isEmpty { parts.append("Highlighted.") }
        parts.append(post.segment.text)
        return parts.joined(separator: " ")
    }
}
