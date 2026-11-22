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
    /// Bookmark highlights (yellow uses the marker colour).
    static let lightRedMarker: UInt32 = 0xFFD9D9
    static let lightBlueMarker: UInt32 = 0xD6E9FF
    /// Bookmark icons.
    static let lightYellowIcon: UInt32 = 0xA87800
    static let lightRedIcon: UInt32 = 0xD0021B
    static let lightBlueIcon: UInt32 = 0x1A73C8

    static let darkBackground: UInt32 = 0x000000
    static let darkSecondaryBackground: UInt32 = 0x16181C
    static let darkPrimary: UInt32 = 0xE7E9EA
    /// A little lighter than X's dark grey (0x71767B, 4.6:1), for margin.
    static let darkSecondary: UInt32 = 0x7E858B
    static let darkHighlight: UInt32 = 0x452912
    static let darkMarker: UInt32 = 0x4A3D00
    static let darkRedMarker: UInt32 = 0x5A1B1F
    static let darkBlueMarker: UInt32 = 0x13324F
    static let darkYellowIcon: UInt32 = 0xFFD400
    static let darkRedIcon: UInt32 = 0xF4212E
    static let darkBlueIcon: UInt32 = 0x1D9BF0

    static let sepiaBackground: UInt32 = 0xF8F0E0
    static let sepiaSecondaryBackground: UInt32 = 0xF1E6CF
    static let sepiaPrimary: UInt32 = 0x3D2E1F
    static let sepiaSecondary: UInt32 = 0x6B5A45
    static let sepiaHighlight: UInt32 = 0xEEDCB8
    static let sepiaMarker: UInt32 = 0xF0D98A
    static let sepiaRedMarker: UInt32 = 0xF0C8BC
    static let sepiaBlueMarker: UInt32 = 0xCCDDE6
    static let sepiaYellowIcon: UInt32 = 0x946A00
    static let sepiaRedIcon: UInt32 = 0xB3261E
    static let sepiaBlueIcon: UInt32 = 0x1E64A8

    /// The colour `t` of the way from `a` to `b`, channel by channel (0 is `a`, 1 is `b`).
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let t = t.isFinite ? min(max(t, 0), 1) : 0
        var result: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            result |= UInt32((x + (y - x) * t).rounded()) << shift
        }
        return result
    }

    /// `color`, moved towards `end` in steps of 2% until it reaches `target` contrast on every
    /// colour of `backgrounds`. Unchanged when it already does; `end` when nothing earlier does.
    static func readable(_ color: UInt32, on backgrounds: [UInt32], target: Double, toward end: UInt32) -> UInt32 {
        for step in 0...50 {
            let candidate = mix(color, end, Double(step) / 50)
            if backgrounds.allSatisfy({ contrast(candidate, $0) >= target }) { return candidate }
        }
        return end
    }

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

/// Colours of the current theme at its brightness (Settings > Theme). System follows the
/// device: Light by day, Night by night. Every text colour reaches its contrast target (see
/// `ThemePalette.readable()`). Reading `AppSettings.shared` inside a view body makes the view
/// update when the theme or brightness changes.
@MainActor
enum Theme {
    private static var cache: (theme: AppTheme, brightness: Double, palette: ThemePalette)?
    private static let systemLight = AppTheme.light.palette(brightness: AppTheme.light.defaultBrightness)
    private static let systemDark = AppTheme.night.palette(brightness: AppTheme.night.defaultBrightness)

    /// The current palette; nil for System, whose colours change with the device.
    static var palette: ThemePalette? {
        let settings = AppSettings.shared
        let theme = settings.theme
        guard theme.hasBrightness else { return nil }
        let brightness = settings.brightness(for: theme)
        if let cache, cache.theme == theme, cache.brightness == brightness { return cache.palette }
        let palette = theme.palette(brightness: brightness)
        cache = (theme, brightness, palette)
        return palette
    }

    private static func color(_ value: (ThemePalette) -> UInt32) -> Color {
        if let palette { return Color(uiColor: UIColor(hex: value(palette))) }
        let (light, dark) = (value(systemLight), value(systemDark))
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static var background: Color { color(\.background) }
    /// Grouped rows (Settings) and cards.
    static var secondaryBackground: Color { color(\.secondaryBackground) }
    static var primaryText: Color { color(\.primary) }
    static var secondaryText: Color { color(\.secondary) }
    static var separator: Color { color(\.separator) }
    static var threadLine: Color { color(\.threadLine) }
    /// Background of the tapped post in the reader. Opaque, so text on it keeps full contrast.
    static var highlight: Color { color(\.highlight) }
    /// Background of the reader's own highlights. Opaque; primary text keeps 7:1 or more.
    static var marker: Color { color(\.marker) }
    static var accent: Color { accent(AppSettings.shared.accent) }
    /// The shade of `choice` that reads as text on the current background.
    static func accent(_ choice: AccentChoice) -> Color { color { $0.accent(choice) } }

    /// Text background of a bookmark in `color`; nil for a bookmark without a highlight.
    static func bookmarkHighlight(_ color: MarkColor) -> Color? {
        switch color {
        case .noHighlight: return nil
        case .yellow: return marker
        case .red: return self.color(\.redMarker)
        case .blue: return self.color(\.blueMarker)
        }
    }

    /// Colour of a bookmark icon or colour dot. A bookmark without a highlight uses the accent.
    static func bookmarkIcon(_ color: MarkColor) -> Color {
        switch color {
        case .noHighlight: return accent
        case .yellow: return self.color(\.yellowIcon)
        case .red: return self.color(\.redIcon)
        case .blue: return self.color(\.blueIcon)
        }
    }

    /// A small preview of `theme` at its stored brightness: background and text colours.
    static func swatch(_ theme: AppTheme) -> (background: Color, text: Color) {
        guard theme.hasBrightness else {
            func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
                Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
            }
            return (dynamic(systemLight.background, systemDark.background), dynamic(systemLight.primary, systemDark.primary))
        }
        let palette = theme.palette(brightness: AppSettings.shared.brightness(for: theme))
        return (Color(uiColor: UIColor(hex: palette.background)), Color(uiColor: UIColor(hex: palette.primary)))
    }
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
    /// Adds a bookmark (no highlight), or removes the post's bookmarks.
    var bookmark: () -> Void
    /// Adds a bookmark (no highlight) when the post has none (double tap).
    var addBookmark: () -> Void = {}
    /// Gives the post's bookmark a colour, bookmarking it first when needed.
    var setBookmarkColor: (_ color: MarkColor) -> Void = { _ in }
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

/// Single tap opens the reader. With double-tap to bookmark on, a double tap bookmarks the post
/// and the single tap waits for the double tap to fail.
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
/// progress, and the text. The bookmark sits beside "⋯" at the top right; read in context and
/// share sit under the avatar, so there is no action bar under the text. A bookmark with a
/// colour highlights the text in it. Focus mode shows the text only.
@MainActor
struct PostRow: View {
    let post: FeedPost
    /// Colour of the post's bookmark; nil when the post has no bookmark.
    let bookmarkColor: MarkColor?
    /// The reader's highlights inside this post, as UTF-16 ranges of the post text.
    var highlights: [NSRange] = []
    /// Coloured bookmarks inside this post, as UTF-16 ranges of the post text.
    var bookmarkHighlights: [MarkerRange] = []
    let actions: PostActions

    private var isBookmarked: Bool { bookmarkColor != nil }

    @State private var expanded = false
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var bookmarkBurst = false
    /// The bubble of bookmark colours beside the bookmark button.
    @State private var showsColorBubble = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    /// Room kept free at the right of the title line for the bookmark and "⋯" buttons.
    private static let topTrailingInset: CGFloat = 80
    /// Height of one button under the avatar (the minimum touch target).
    private static let columnButtonHeight: CGFloat = 44
    private static let columnButtonCount: CGFloat = 2
    /// The colour bubble closes by itself after this many seconds.
    private static let bubbleSeconds: UInt64 = 5
    /// Gap between the avatar and the first button under it.
    private static let columnGap: CGFloat = 4

    private var isTruncated: Bool { !expanded && fullHeight > limitedHeight + 1 }

    /// Post text size from Settings, in points. The title and author use it too, as on X.
    /// The accessibility text sizes (Larger Accessibility Sizes) still enlarge it.
    private var textSize: CGFloat {
        let size = CGFloat(settings.postTextSize)
        return dynamicTypeSize.isAccessibilitySize ? UIFontMetrics(forTextStyle: .body).scaledValue(for: size) : size
    }

    private var textFont: Font { settings.postTypeface.font(size: textSize) }

    /// The chapter and progress line, at X's 13:15 ratio to the text.
    private var smallFont: Font { .system(size: textSize * 13 / 15) }

    /// Extra space between lines so lines are 1.25 times the text size, as in the X app.
    private var textLineSpacing: CGFloat {
        let natural = settings.postTypeface.uiFont(size: textSize).lineHeight
        return max(0, PostTextSize.lineHeight(for: textSize) - natural)
    }

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
                VStack(spacing: 0) {
                    Button(action: actions.open) {
                        AvatarView(title: post.bookTitle, author: post.bookAuthor, size: avatarSize, textStyle: .title3, bookID: post.bookID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Read \(post.bookTitle) in context")
                    .padding(.bottom, Self.columnGap)
                    avatarColumnButtons
                }
                .frame(width: avatarSize)
            }

            VStack(alignment: .leading, spacing: 2) {
                textGroup
                    .overlay(alignment: .topTrailing) {
                        if !focusMode { topTrailingButtons }
                    }
                if isTruncated {
                    Button("Show more") { expanded = true }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityHint("Shows the whole post")
                        .accessibilityIdentifier("post.showMore")
                        .font(.system(size: textSize, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, focusMode ? topPadding + 6 : topPadding)
        .padding(.bottom, focusMode ? topPadding + 6 : topPadding)
    }

    /// Split into steps so the type checker stays fast (Xcode 16 times out on one long chain).
    private var textGroup: some View {
        postAccessibility(postInteractions(textStack))
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: isCompact ? 1 : 2) {
            if showsChapterStartLine {
                Label("New chapter \u{00B7} \(post.segment.chapter)", systemImage: "book.pages")
                    .font(.system(size: textSize * 13 / 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.trailing, focusMode ? 0 : Self.topTrailingInset)
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
                .padding(.trailing, showsChapterStartLine ? 0 : Self.topTrailingInset)
                if !post.progressLine.isEmpty {
                    Text(post.progressLine)
                        .font(smallFont)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            postText
                .padding(.top, focusMode ? 0 : 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Taps, the bookmark burst, drag and the long-press peek.
    private func postInteractions<Content: View>(_ content: Content) -> some View {
        content
        .modifier(PostTapGestures(doubleTapEnabled: settings.doubleTapToBookmark, onSingle: actions.open, onDouble: doubleTapBookmark))
        .overlay {
            if bookmarkBurst {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.bookmarkIcon(bookmarkColor ?? .noHighlight))
                    .shadow(color: .black.opacity(0.25), radius: 6)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        // Drag the post to another app (iPad, Mac) as text with its citation.
        .draggable(ShareFormatter.citation(post))
        .contextMenu {
            contextMenuItems
        } preview: {
            if let peek = actions.peek() {
                PeekView(content: peek)
            } else {
                PeekView(content: PeekContent(bookTitle: post.bookTitle, progressLine: post.fullProgressLine, before: [], post: [post.segment], after: [], highlight: post.segment.charStart..<post.segment.charEnd))
            }
        }
    }

    /// One VoiceOver element per post, with its actions.
    private func postAccessibility<Content: View>(_ content: Content) -> some View {
        content
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to read in context")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, actions.open)
        .accessibilityAction(named: isBookmarked ? "Remove bookmark" : "Bookmark", actions.bookmark)
        .accessibilityAction(named: "Bookmark with no highlight") { actions.setBookmarkColor(.noHighlight) }
        .accessibilityAction(named: "Bookmark in yellow") { actions.setBookmarkColor(.yellow) }
        .accessibilityAction(named: "Bookmark in red") { actions.setBookmarkColor(.red) }
        .accessibilityAction(named: "Bookmark in blue") { actions.setBookmarkColor(.blue) }
        .accessibilityAction(named: highlights.isEmpty ? "Highlight" : "Remove highlight", actions.highlight)
        .accessibilityAction(named: "Copy with citation") { actions.copy(true) }
        .accessibilityIdentifier("post")
    }

    /// Long-press menu under the context peek.
    @ViewBuilder
    private var contextMenuItems: some View {
        Button(action: actions.bookmark) {
            Label(isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark")
        }
        Menu {
            ForEach(MarkColor.allCases) { color in
                Button { actions.setBookmarkColor(color) } label: {
                    if bookmarkColor == color {
                        Label(color.title, systemImage: "checkmark")
                    } else {
                        Text(color.title)
                    }
                }
            }
        } label: {
            Label("Bookmark colour", systemImage: "paintpalette")
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
        .accessibilityLabel("More options for \(post.bookTitle)")
        .accessibilityIdentifier("post.more")
    }

    /// Bookmark beside X's "⋯" menu at the top right of the post. The colour bubble is a
    /// popover from the bookmark: a tap outside it only closes it (the system keeps that tap
    /// from reaching the post or the tab bar behind it).
    private var topTrailingButtons: some View {
        HStack(spacing: 0) {
            Button(action: bookmarkTapped) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.subheadline)
                    .foregroundStyle(isBookmarked ? Theme.bookmarkIcon(bookmarkColor ?? .noHighlight) : Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isBookmarked ? "Change bookmark" : "Bookmark")
            .accessibilityValue(bookmarkValue)
            .accessibilityIdentifier("post.bookmark")
            .popover(isPresented: $showsColorBubble, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                colorBubble
                    .presentationCompactAdaptation(.popover)
                    .presentationBackground(Theme.secondaryBackground)
            }
            moreMenu
        }
        .offset(x: 12, y: -12)
        .task(id: showsColorBubble) {
            guard showsColorBubble else { return }
            try? await Task.sleep(nanoseconds: Self.bubbleSeconds * 1_000_000_000)
            if !Task.isCancelled { setBubble(false) }
        }
        .onDisappear { showsColorBubble = false }
    }

    private var bookmarkValue: String {
        guard let bookmarkColor else { return String(localized: "Not bookmarked") }
        return bookmarkColor.highlightsText
            ? String(localized: "Bookmarked, \(bookmarkColor.title) highlight")
            : String(localized: "Bookmarked, no highlight")
    }

    /// The first tap bookmarks the post (no highlight) and opens the colours; on a bookmarked
    /// post the tap opens or closes the colours, which also hold Remove.
    private func bookmarkTapped() {
        if !isBookmarked {
            actions.bookmark()
            setBubble(true)
        } else {
            setBubble(!showsColorBubble)
        }
    }

    private func setBubble(_ shown: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.75)) {
            showsColorBubble = shown
        }
        if shown {
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Bookmarked. Choose a highlight colour."))
        }
    }

    /// No highlight, yellow, red and blue, then Remove bookmark.
    private var colorBubble: some View {
        HStack(spacing: 0) {
            ForEach(MarkColor.allCases) { color in
                Button {
                    actions.setBookmarkColor(color)
                    setBubble(false)
                } label: {
                    BookmarkColorDot(color: color, size: 22, isSelected: bookmarkColor == color)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(color.title)
                .accessibilityAddTraits(bookmarkColor == color ? .isSelected : [])
                .accessibilityIdentifier("bookmark.color.\(color.rawValue)")
            }
            Button {
                actions.bookmark()
                setBubble(false)
            } label: {
                Image(systemName: "bookmark.slash")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Remove bookmark")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bookmark colours")
    }

    /// Double tap only bookmarks (never removes), shows a bookmark and opens the colours.
    private func doubleTapBookmark() {
        if !isBookmarked {
            actions.addBookmark()
            setBubble(true)
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { bookmarkBurst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { bookmarkBurst = false }
        }
    }

    private var titleText: some View {
        Text(post.bookTitle)
            .font(settings.postTypeface.font(size: textSize, bold: true))
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var authorText: some View {
        Text(post.bookAuthor)
            .font(settings.postTypeface.font(size: textSize))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The post text with the bookmark colour and the reader's highlights (drawn over it).
    private var markedText: AttributedString {
        var text = AttributedString(post.segment.text)
        for marker in bookmarkHighlights {
            guard let color = Theme.bookmarkHighlight(marker.color), let bounds = Range(marker.range, in: text) else { continue }
            text[bounds][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = color
        }
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

    /// Read in context and share, one above the other under the avatar. Each is a full
    /// 44 pt touch target; the column is as wide as the avatar and the targets reach a little
    /// past it.
    private var avatarColumnButtons: some View {
        VStack(spacing: 0) {
            Button(action: actions.open) {
                Image(systemName: "book")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: Self.columnButtonHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Read in context")
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
                    .frame(width: 44, height: Self.columnButtonHeight)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share")
        }
        .font(.subheadline)
        .buttonStyle(.borderless)
        .frame(width: avatarSize)
    }

    /// Thin vertical line through the avatar column that joins the posts of a thread.
    private var threadLines: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.threadLine)
                .frame(width: 2, height: max(0, topPadding - 2))
                .opacity(post.continuesThread ? 1 : 0)
            // The avatar and the buttons under it.
            Color.clear
                .frame(width: 2, height: avatarSize + Self.columnGap + Self.columnButtonHeight * Self.columnButtonCount + 4)
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
        if let bookmarkColor {
            parts.append(bookmarkColor.highlightsText ? "Bookmarked, \(bookmarkColor.title) highlight." : "Bookmarked.")
        }
        if !highlights.isEmpty { parts.append("Highlighted.") }
        parts.append(post.segment.text)
        return parts.joined(separator: " ")
    }
}

/// A bookmark colour as a dot: a filled circle, or a struck-through circle for no highlight.
/// A selected colour has a ring.
@MainActor
struct BookmarkColorDot: View {
    let color: MarkColor
    var size: CGFloat = 22
    var isSelected = false

    var body: some View {
        ZStack {
            if color.highlightsText {
                Circle()
                    .fill(Theme.bookmarkIcon(color))
            } else {
                Image(systemName: "circle.slash")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Theme.secondaryText)
            }
            if isSelected {
                Circle()
                    .strokeBorder(Theme.primaryText, lineWidth: 2)
                    .padding(-4)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
