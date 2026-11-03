import SwiftUI

struct FeedView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue
    @AppStorage("feedMode") private var modeRaw = "mix"
    @AppStorage("singleBookID") private var singleBookID = ""

    private var selectedStyle: PostStyle { PostStyle(rawValue: styleRaw) ?? .paragraph }

    private var selectedMode: FeedMode {
        if modeRaw == "single", let id = UUID(uuidString: singleBookID) {
            return .single(id)
        }
        return .mix
    }

    /// "mix" or a book id. Drives the mode picker.
    private var modeSelection: Binding<String> {
        Binding(
            get: { modeRaw == "single" ? singleBookID : "mix" },
            set: { value in
                if value == "mix" {
                    modeRaw = "mix"
                } else {
                    singleBookID = value
                    modeRaw = "single"
                }
            }
        )
    }

    var body: some View {
        let feed = app.feed
        NavigationStack {
            Group {
                if feed.books.isEmpty {
                    ContentUnavailableView {
                        Label("No books yet", systemImage: "books.vertical")
                    } description: {
                        Text("Import DRM-free EPUB or PDF files to fill your feed.")
                    } actions: {
                        Button { app.presentImporter() } label: {
                            Text("Import Books").foregroundStyle(Theme.background)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Opens Files to pick EPUB or PDF files")
                        .accessibilityIdentifier("feed.empty.import")
                    }
                } else {
                    timeline
                }
            }
            .background(Theme.background)
            .navigationTitle(feed.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { modeMenu }
                ToolbarItem(placement: .topBarTrailing) { styleMenu }
            }
        }
        .task { feed.configure(style: selectedStyle, mode: selectedMode) }
        .onChange(of: styleRaw) { feed.configure(style: selectedStyle, mode: selectedMode) }
        .onChange(of: modeRaw) { feed.configure(style: selectedStyle, mode: selectedMode) }
        .onChange(of: singleBookID) { feed.configure(style: selectedStyle, mode: selectedMode) }
        .onChange(of: feed.mode) { _, mode in
            if mode == .mix && modeRaw != "mix" { modeRaw = "mix" }
        }
    }

    private var timeline: some View {
        @Bindable var feed = app.feed
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(feed.posts) { post in
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
                    .onAppear { feed.postAppeared(post.id) }
                }
                FeedFooter(isAtEnd: feed.isAtEnd)
                    .id("feed-footer")
                    .onAppear { feed.loadMore() }
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $feed.scrolledID)
        .refreshable { feed.refresh() }
        .onChange(of: feed.scrolledID) { _, id in feed.didScroll(to: id) }
    }

    private var modeMenu: some View {
        Menu {
            Picker("Feed mode", selection: modeSelection) {
                Label("Mix all books", systemImage: "shuffle").tag("mix")
                Section("One book") {
                    ForEach(app.feed.books) { book in
                        Text(book.title).tag(book.id.uuidString)
                    }
                }
            }
        } label: {
            Image(systemName: selectedModeIsMix ? "shuffle" : "book.closed")
        }
        .accessibilityLabel("Feed mode")
        .accessibilityValue(selectedModeIsMix ? "Mix all books" : "One book: \(app.feed.title)")
    }

    private var selectedModeIsMix: Bool {
        if case .mix = app.feed.mode { return true }
        return false
    }

    private var styleMenu: some View {
        Menu {
            Picker("Post style", selection: $styleRaw) {
                ForEach(PostStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            }
        } label: {
            Image(systemName: selectedStyle == .paragraph ? "text.alignleft" : "rectangle.split.1x2")
        }
        .accessibilityLabel("Post style")
        .accessibilityValue(selectedStyle.title)
    }
}

private struct FeedFooter: View {
    let isAtEnd: Bool

    var body: some View {
        Group {
            if isAtEnd {
                Text("You have reached the end of your books.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading more posts")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
