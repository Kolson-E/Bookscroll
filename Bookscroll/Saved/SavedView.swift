import SwiftUI

struct SavedView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue
    @State private var filter: SavedFilter = .all
    @State private var posts: [FeedPost] = []

    private var reloadKey: String {
        "\(filter.rawValue)|\(styleRaw)|\(app.marks.version)|\(app.libraryVersion)"
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
                Divider()
                if posts.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: filter == .liked ? "heart" : "bookmark")
                    } description: {
                        Text("Like or bookmark posts in the feed to keep them here.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(posts) { post in
                                PostRow(
                                    post: post,
                                    isLiked: app.marks.isMarked(.like, post),
                                    isBookmarked: app.marks.isMarked(.bookmark, post),
                                    onLike: { app.marks.toggle(.like, post) },
                                    onBookmark: { app.marks.toggle(.bookmark, post) },
                                    onOpen: { app.openReader(for: post) },
                                    onShareText: { app.shareText(post) },
                                    onShareImage: { app.shareImage(post) }
                                )
                            }
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task(id: reloadKey) {
            posts = app.savedPosts(filter: filter, style: PostStyle(rawValue: styleRaw) ?? .paragraph)
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return "Nothing saved yet"
        case .liked: return "No liked posts"
        case .bookmarked: return "No bookmarks"
        }
    }
}
