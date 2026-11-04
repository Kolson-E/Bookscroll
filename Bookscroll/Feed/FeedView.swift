import SwiftUI

@MainActor
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue
    @AppStorage("feedMode") private var modeRaw = "mix"
    @AppStorage("singleBookID") private var singleBookID = ""
    @AppStorage("feedShelfID") private var feedShelfID = ""

    private var selectedStyle: PostStyle { PostStyle(rawValue: styleRaw) ?? .paragraph }

    @AppStorage(FocusFeed.key) private var focusShelfID = ""

    private var selectedMode: FeedMode {
        FeedModeChoice.resolve(
            modeRaw: modeRaw,
            singleBookID: singleBookID,
            feedShelfID: feedShelfID,
            focusShelfID: focusShelfID,
            shelves: app.shelves.shelves
        )
    }

    /// The shelf a Focus filter shows now, if any.
    private var focusShelf: ShelfRecord? {
        UUID(uuidString: focusShelfID).flatMap { app.shelves.shelf(id: $0) }
    }

    private static let shelfTagPrefix = "shelf:"

    /// "mix", a book id, or "shelf:" and a shelf id. Drives the mode picker.
    private var modeSelection: Binding<String> {
        Binding(
            get: {
                if focusShelf != nil { return Self.shelfTagPrefix + focusShelfID }
                switch modeRaw {
                case "single": return singleBookID
                case "shelf": return Self.shelfTagPrefix + feedShelfID
                default: return "mix"
                }
            },
            set: { value in
                // Your own choice ends the Focus shelf until the Focus changes again.
                focusShelfID = ""
                if value == "mix" {
                    modeRaw = "mix"
                } else if value.hasPrefix(Self.shelfTagPrefix) {
                    feedShelfID = String(value.dropFirst(Self.shelfTagPrefix.count))
                    modeRaw = "shelf"
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
                        Text("Import DRM-free books or paste text to fill your feed.")
                        .foregroundStyle(Theme.secondaryText)
                    } actions: {
                        Button { app.presentImporter() } label: {
                            Text("Import Books").foregroundStyle(Theme.background)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Opens Files to pick books")
                        .accessibilityIdentifier("feed.empty.import")
                    }
                } else {
                    timeline
                }
            }
            .background(Theme.background)
            .navigationTitle(feed.title)
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { modeMenu }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let id = singleModeBookID {
                        Button {
                            app.presentJump(bookID: id)
                        } label: {
                            Image(systemName: "list.bullet.indent")
                        }
                        .accessibilityLabel("Jump to")
                        .accessibilityHint("Chapters and percent")
                    }
                    styleMenu
                }
            }
        }
        .task { configureFeed() }
        .onChange(of: styleRaw) { configureFeed() }
        .onChange(of: modeRaw) { configureFeed() }
        .onChange(of: singleBookID) { configureFeed() }
        .onChange(of: feedShelfID) { configureFeed() }
        .onChange(of: focusShelfID) { configureFeed() }
        .onChange(of: app.shelves.shelves) { configureFeed() }
        .onChange(of: AppSettings.shared.wordLimit) { configureFeed() }
        .onChange(of: feed.mode) { _, mode in
            if mode == .mix && modeRaw != "mix" { modeRaw = "mix" }
        }
    }

    private func configureFeed() {
        app.feed.configure(style: selectedStyle, mode: selectedMode, wordLimit: AppSettings.shared.wordLimit)
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
                        highlights: app.marks.highlightRanges(for: post),
                        actions: app.actions(for: post)
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
            // Buttons, not a Picker: iOS 17 drops the sections of a Picker inside a Menu.
            let selection = modeSelection
            if let focusShelf {
                Section {
                    Button("Focus shows \u{201C}\(focusShelf.name)\u{201D}. A choice below ends it.") {}
                        .disabled(true)
                }
            }
            MenuChoice(title: "Mix all books", symbol: "shuffle", isSelected: selection.wrappedValue == "mix") {
                selection.wrappedValue = "mix"
            }
            if !app.shelves.shelves.isEmpty {
                Section("Shelf") {
                    ForEach(app.shelves.shelves) { shelf in
                        let tag = Self.shelfTagPrefix + shelf.id.uuidString
                        MenuChoice(title: shelf.name, isSelected: selection.wrappedValue == tag) {
                            selection.wrappedValue = tag
                        }
                    }
                }
            }
            Section("One book") {
                ForEach(app.feed.books) { book in
                    let tag = book.id.uuidString
                    MenuChoice(title: book.title, isSelected: selection.wrappedValue == tag) {
                        selection.wrappedValue = tag
                    }
                }
            }
        } label: {
            Image(systemName: modeSymbol)
        }
        .accessibilityLabel("Feed mode")
        .accessibilityValue(modeDescription)
    }

    private var modeSymbol: String {
        switch app.feed.mode {
        case .mix: return "shuffle"
        case .single: return "book.closed"
        case .shelf: return "books.vertical"
        }
    }

    private var modeDescription: String {
        switch app.feed.mode {
        case .mix: return "Mix all books"
        case .single: return "One book: \(app.feed.title)"
        case let .shelf(shelf): return "Shelf: \(shelf.name)"
        }
    }

    /// The book of One book mode; nil in Mix.
    private var singleModeBookID: UUID? {
        if case let .single(id) = app.feed.mode { return id }
        return nil
    }

    private var styleMenu: some View {
        Menu {
            ForEach(PostStyle.allCases) { style in
                MenuChoice(title: style.title, isSelected: styleRaw == style.rawValue) {
                    styleRaw = style.rawValue
                }
            }
            Divider()
            Toggle(isOn: Bindable(AppSettings.shared).focusMode) {
                Label("Focus mode", systemImage: "text.justify.left")
            }
        } label: {
            Image(systemName: selectedStyle == .paragraph ? "text.alignleft" : "rectangle.split.1x2")
        }
        .accessibilityLabel("Post style")
        .accessibilityValue(selectedStyle.title)
    }
}

/// One choice in a menu: a checkmark when selected, else its symbol (if any).
@MainActor
struct MenuChoice: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else if let symbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

@MainActor
private struct FeedFooter: View {
    let isAtEnd: Bool

    var body: some View {
        Group {
            if isAtEnd {
                Text("You have reached the end of your books.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ProgressView()
                    .accessibilityLabel("Loading more posts")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
