import SwiftUI
import UIKit

enum Theme {
    /// White in light mode, pure black in dark mode.
    static let background = Color(uiColor: .systemBackground)
    static let threadLine = Color(uiColor: .systemGray4)
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

    static func color(title: String, author: String) -> Color {
        Color(hue: hue(for: title + "|" + author), saturation: 0.55, brightness: 0.62)
    }
}

struct AvatarView: View {
    let title: String
    let author: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(BookColor.color(title: title, author: author))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.46, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
    }

    private var initial: String {
        if let first = title.first(where: { $0.isLetter || $0.isNumber }) {
            return String(first).uppercased()
        }
        return "?"
    }
}

struct ChapterHeaderRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.book.closed")
                .imageScale(.small)
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chapter: \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// One timeline post: avatar, title line, author, chapter and progress, serif text, actions.
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
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 44

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
                if isTruncated {
                    Button("Show more") { expanded = true }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                        .accessibilityHint("Shows the whole post")
                }
                if post.showsThreadButton {
                    Button("Show thread", action: onOpen)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                        .accessibilityHint("Opens the book around this post")
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
            HStack(spacing: 4) {
                Text(post.bookTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(post.bookAuthor)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(post.progressLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
                    .foregroundStyle(isLiked ? Color.pink : Color.secondary)
                    .frame(minWidth: 44, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isLiked ? "Unlike" : "Like")
            .accessibilityValue(isLiked ? "Liked" : "Not liked")
            Spacer(minLength: 0)
            Button(action: onBookmark) {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 44, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark")
            .accessibilityValue(isBookmarked ? "Bookmarked" : "Not bookmarked")
            Spacer(minLength: 0)
            Button(action: onOpen) {
                Image(systemName: "book")
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 44, minHeight: 36)
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
                    .foregroundStyle(Color.secondary)
                    .frame(minWidth: 44, minHeight: 36, alignment: .trailing)
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
