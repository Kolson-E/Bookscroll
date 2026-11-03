import SwiftUI
import UIKit

enum Theme {
    /// White in light mode, pure black in dark mode.
    static let background = Color(uiColor: .systemBackground)
    static let threadLine = Color(uiColor: .systemGray4)
    /// Background of the tapped post in the reader. Opaque, so text on it keeps full contrast.
    static let highlight = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.16, blue: 0.07, alpha: 1)
            : UIColor(red: 0.99, green: 0.91, blue: 0.85, alpha: 1)
    })
    /// Secondary text with at least 4.5:1 contrast on the background (the system
    /// secondary label colour is about 3.4:1 on white).
    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.64, green: 0.64, blue: 0.67, alpha: 1)
            : UIColor(red: 0.38, green: 0.38, blue: 0.41, alpha: 1)
    })
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

    var body: some View {
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

    private var initial: String {
        if let first = title.first(where: { $0.isLetter || $0.isNumber }) {
            return String(first).uppercased()
        }
        return "?"
    }
}

@MainActor
struct ChapterHeaderRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.book.closed")
                .imageScale(.small)
            Text(title)
                .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.secondaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chapter: \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One timeline post: avatar, title line, author, chapter and progress, serif text, actions.
@MainActor
struct PostRow: View {
    let post: FeedPost
    let isLiked: Bool
    let isBookmarked: Bool
    let onLike: () -> Void
    let onBookmark: () -> Void
    let onOpen: () -> Void
    let onShareText: () -> Void
    let onShareImage: () -> Void

    @State private var expanded = false
    @State private var limitedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .body) private var scaledAvatarSize: CGFloat = 44
    /// Grows with Dynamic Type but stops at 64 pt, so large text keeps a wide text column.
    private var avatarSize: CGFloat { min(scaledAvatarSize, 64) }

    private let horizontalPadding: CGFloat = 16
    private let topPadding: CGFloat = 12
    private static let collapsedLineLimit = 10

    private var isTruncated: Bool { !expanded && fullHeight > limitedHeight + 1 }

    var body: some View {
        VStack(spacing: 0) {
            if let header = post.chapterHeader {
                ChapterHeaderRow(title: header)
                Divider()
            }
            content
                .overlay(alignment: .topLeading) { threadLines }
            if !post.threadContinuesBelow {
                Divider()
            }
        }
        .background(Theme.background)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                AvatarView(title: post.bookTitle, author: post.bookAuthor, size: avatarSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Read \(post.bookTitle) in context")

            VStack(alignment: .leading, spacing: 4) {
                textGroup
                if isTruncated || post.showsThreadButton {
                    HStack(spacing: 20) {
                        if isTruncated {
                            Button("Show more") { expanded = true }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityHint("Shows the whole post")
                                .accessibilityIdentifier("post.showMore")
                        }
                        if post.showsThreadButton {
                            Button("Show thread", action: onOpen)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                                .accessibilityHint("Opens the book around this post")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                }
                actionRow
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, 8)
    }

    private var textGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title and author share a line when they fit, otherwise they stack. Nothing is cut off.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    titleText
                    authorText
                }
                VStack(alignment: .leading, spacing: 2) {
                    titleText
                    authorText
                }
            }
            Text(post.progressLine)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            postText
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double-tap to read in context")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
        .accessibilityIdentifier("post")
    }

    private var titleText: some View {
        Text(post.bookTitle)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var authorText: some View {
        Text(post.bookAuthor)
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var postText: some View {
        Text(post.segment.text)
            .font(.system(.body, design: .serif))
            .foregroundStyle(.primary)
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
                        .font(.system(.body, design: .serif))
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
            Button(action: onLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? Color.pink : Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isLiked ? "Unlike" : "Like")
            .accessibilityValue(isLiked ? "Liked" : "Not liked")
            Spacer(minLength: 0)
            Button(action: onBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? Color.accentColor : Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark")
            .accessibilityValue(isBookmarked ? "Bookmarked" : "Not bookmarked")
            Spacer(minLength: 0)
            Button(action: onOpen) {
                Image(systemName: "book")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Read in context")
            Spacer(minLength: 0)
            Menu {
                Button(action: onShareText) {
                    Label("Share as text", systemImage: "text.quote")
                }
                Button(action: onShareImage) {
                    Label("Share as image card", systemImage: "photo")
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
        parts.append("\(post.bookTitle), by \(post.bookAuthor).")
        if !post.segment.chapter.isEmpty { parts.append("\(post.segment.chapter).") }
        parts.append("\(post.percent) percent.")
        if isLiked { parts.append("Liked.") }
        if isBookmarked { parts.append("Bookmarked.") }
        parts.append(post.segment.text)
        return parts.joined(separator: " ")
    }
}
