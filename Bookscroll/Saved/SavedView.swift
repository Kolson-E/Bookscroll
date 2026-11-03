import SwiftUI

/// Saved: Bookmarks (the reader's own feed of saved places), Likes and Highlights.
@MainActor
struct SavedView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue
    @AppStorage("savedFilter") private var filter: SavedFilter = .bookmarked
    @State private var posts: [FeedPost] = []
    @State private var highlights: [HighlightItem] = []

    private var reloadKey: String {
        "\(filter.rawValue)|\(styleRaw)|\(app.marks.version)|\(app.libraryVersion)"
    }

    private var isEmpty: Bool {
        filter == .highlights ? highlights.isEmpty : posts.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filter) {
                    ForEach(SavedFilter.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .accessibilityLabel("Show saved posts")
                ThemedDivider()
                if isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptySymbol)
                    } description: {
                        Text(emptyDescription)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if filter == .highlights {
                                ForEach(highlights) { item in
                                    HighlightRow(item: item)
                                }
                            } else {
                                ForEach(posts) { post in
                                    PostRow(
                                        post: post,
                                        isLiked: app.marks.isMarked(.like, post),
                                        isBookmarked: app.marks.isMarked(.bookmark, post),
                                        highlights: app.marks.highlightRanges(for: post),
                                        actions: app.actions(for: post)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
        }
        .task(id: reloadKey) {
            if filter == .highlights {
                highlights = app.highlights()
                posts = []
            } else {
                posts = app.savedPosts(filter: filter, style: PostStyle(rawValue: styleRaw) ?? .paragraph)
                highlights = []
            }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .bookmarked: return "No bookmarks"
        case .liked: return "No liked posts"
        case .highlights: return "No highlights"
        }
    }

    private var emptySymbol: String {
        switch filter {
        case .bookmarked: return "bookmark"
        case .liked: return "heart"
        case .highlights: return "highlighter"
        }
    }

    private var emptyDescription: String {
        switch filter {
        case .bookmarked: return "Bookmark posts in the feed to keep your places here."
        case .liked: return "Like posts in the feed to keep them here."
        case .highlights: return "Select text in the reader and choose Highlight, or touch and hold a post and choose Highlight."
        }
    }
}

/// A highlight in Saved: the highlighted text on the marker colour, and where it is from.
/// Tap opens the reader there.
@MainActor
private struct HighlightRow: View {
    @Environment(AppModel.self) private var app
    let item: HighlightItem

    private var source: String {
        var parts = [item.bookTitle]
        if !item.chapter.isEmpty { parts.append(item.chapter) }
        parts.append("\(item.percent)%")
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                app.openReader(bookID: item.mark.bookID, charStart: item.mark.charStart, charEnd: item.mark.charEnd)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(source)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.text)
                        .font(.system(.callout, design: AppSettings.shared.readerTypeface.design))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.marker, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.mark.createdAt, format: .dateTime.day().month().year())
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    app.openReader(bookID: item.mark.bookID, charStart: item.mark.charStart, charEnd: item.mark.charEnd)
                } label: {
                    Label("Read in context", systemImage: "book")
                }
                Button {
                    app.copyHighlight(item)
                } label: {
                    Label("Copy with citation", systemImage: "quote.bubble")
                }
                Button {
                    app.shareImage(item)
                } label: {
                    Label("Share as image", systemImage: "photo")
                }
                Button(role: .destructive) {
                    app.marks.removeHighlights(bookID: item.mark.bookID, start: item.mark.charStart, end: item.mark.charEnd)
                } label: {
                    Label("Remove highlight", systemImage: "highlighter")
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Highlight. \(item.text). \(item.bookTitle)\(item.chapter.isEmpty ? "" : ", \(item.chapter)"), \(item.percent) percent.")
            .accessibilityHint("Opens the book here")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Copy with citation") { app.copyHighlight(item) }
            .accessibilityAction(named: "Remove highlight") {
                app.marks.removeHighlights(bookID: item.mark.bookID, start: item.mark.charStart, end: item.mark.charEnd)
            }
            .accessibilityIdentifier("highlight")
            ThemedDivider()
        }
        .background(Theme.background)
    }
}
