import SwiftUI

@MainActor
struct FeedView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue
    @AppStorage("feedMode") private var modeRaw = "mix"
    @AppStorage("singleBookID") private var singleBookID = ""
    @AppStorage("feedShelfID") private var feedShelfID = ""
    @AppStorage(FeedModeChoice.chosenBooksKey) private var chosenBookIDs = ""
    @State private var isChoosingBooks = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    /// The bars hide while you read, as on X; not with VoiceOver, and not in UI tests unless
    /// a test asks for it.
    private var hidesBarsOnScroll: Bool {
        if ProcessInfo.processInfo.arguments.contains("-UITestInMemoryStore") && !Self.tracesBars { return false }
        return !voiceOverEnabled
    }

    /// UI tests of the bars: the app reports how the bars moved (see `ScrollChromeTrace`).
    private static let tracesBars = ProcessInfo.processInfo.arguments.contains("-UITestHideBars")
    @State private var barTrace = ""

    private var selectedStyle: PostStyle { PostStyle(rawValue: styleRaw) ?? .paragraph }

    @AppStorage(FocusFeed.key) private var focusShelfID = ""

    private var selectedMode: FeedMode {
        FeedModeChoice.resolve(
            modeRaw: modeRaw,
            singleBookID: singleBookID,
            feedShelfID: feedShelfID,
            focusShelfID: focusShelfID,
            shelves: app.shelves.shelves,
            chosenBookIDs: chosenBookIDs,
            readingSets: app.readingList.sets
        )
    }

    /// The shelf a Focus filter shows now, if any.
    private var focusShelf: ShelfRecord? {
        UUID(uuidString: focusShelfID).flatMap { app.shelves.shelf(id: $0) }
    }

    private static let shelfTagPrefix = "shelf:"
    private static let chosenTag = "books"

    /// "mix", a book id, or "shelf:" and a shelf id. Drives the mode picker.
    private var modeSelection: Binding<String> {
        Binding(
            get: {
                if focusShelf != nil { return Self.shelfTagPrefix + focusShelfID }
                switch modeRaw {
                case "single": return singleBookID
                case "shelf": return Self.shelfTagPrefix + feedShelfID
                case "books": return Self.chosenTag
                case FeedModeChoice.readingListTag: return FeedModeChoice.readingListTag
                default: return "mix"
                }
            },
            set: { value in
                // Your own choice ends the Focus shelf until the Focus changes again.
                focusShelfID = ""
                if value == "mix" {
                    modeRaw = "mix"
                } else if value == Self.chosenTag {
                    modeRaw = "books"
                } else if value == FeedModeChoice.readingListTag {
                    modeRaw = FeedModeChoice.readingListTag
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
                        Button { app.presentFinder() } label: {
                            Label("Find Books on This iPhone", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Lists the books in the folders you allow")
                        .accessibilityIdentifier("feed.empty.find")
                    }
                } else {
                    timeline
                }
            }
            .background(Theme.background)
            .overlay(alignment: .topLeading) {
                if Self.tracesBars {
                    Color.clear
                        .frame(width: 2, height: 2)
                        .accessibilityElement()
                        .accessibilityLabel("Bar trace")
                        .accessibilityValue(barTrace)
                        .accessibilityIdentifier("feed.barTrace")
                }
            }
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
        .sheet(isPresented: $isChoosingBooks) {
            ChooseFeedBooksSheet(
                initial: chosenForSheet,
                onChoose: chooseBooks,
                onSaveShelf: saveShelf
            )
            .environment(app)
        }
        .task { configureFeed() }
        .onChange(of: styleRaw) { configureFeed() }
        .onChange(of: modeRaw) { configureFeed() }
        .onChange(of: singleBookID) { configureFeed() }
        .onChange(of: feedShelfID) { configureFeed() }
        .onChange(of: chosenBookIDs) { configureFeed() }
        .onChange(of: focusShelfID) { configureFeed() }
        .onChange(of: app.shelves.shelves) { configureFeed() }
        .onChange(of: app.readingList.sets) { configureFeed() }
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
                        bookmarkColor: app.marks.bookmarkColor(post),
                        highlights: app.marks.highlightRanges(for: post),
                        bookmarkHighlights: app.marks.bookmarkHighlights(for: post),
                        actions: app.actions(for: post)
                    )
                    .onAppear { feed.postAppeared(post.id) }
                }
                FeedFooter(isAtEnd: feed.isAtEnd)
                    .id("feed-footer")
                    .onAppear { feed.loadMore() }
            }
            .scrollTargetLayout()
            .background(alignment: .top) {
                ScrollChromeObserver(
                    isEnabled: hidesBarsOnScroll,
                    onTrace: Self.tracesBars ? { barTrace = $0 } : nil
                )
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
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
            MenuChoice(title: chosenMenuTitle, symbol: "checklist", isSelected: selection.wrappedValue == Self.chosenTag) {
                isChoosingBooks = true
            }
            Section {
                MenuChoice(
                    title: String(localized: "Reading list"),
                    symbol: "list.number",
                    isSelected: selection.wrappedValue == FeedModeChoice.readingListTag
                ) {
                    if app.readingList.sets.isEmpty {
                        app.presentReadingList()
                    } else {
                        selection.wrappedValue = FeedModeChoice.readingListTag
                    }
                }
                Button {
                    app.presentReadingList()
                } label: {
                    Label(app.readingList.sets.isEmpty ? LocalizedStringKey("Make a Reading List\u{2026}") : LocalizedStringKey("Edit Reading List\u{2026}"), systemImage: "square.and.pencil")
                }
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
        case .readingList: return "list.number"
        }
    }

    private var modeDescription: String {
        switch app.feed.mode {
        case .mix: return "Mix all books"
        case .single: return "One book: \(app.feed.title)"
        case let .shelf(shelf) where shelf.id == FeedModeChoice.chosenBooksID: return "Chosen books: \(shelf.name)"
        case let .shelf(shelf): return "Shelf: \(shelf.name)"
        case .readingList: return "Reading list: \(app.feed.title)"
        }
    }

    /// "Choose Books…", or the chosen books while they show.
    private var chosenMenuTitle: String {
        if modeRaw == "books", focusShelf == nil {
            let count = FeedModeChoice.bookIDs(from: chosenBookIDs).count
            if count > 1 { return String(localized: "Chosen books (\(count))\u{2026}") }
        }
        return String(localized: "Choose books\u{2026}")
    }

    /// The books the Choose Books sheet starts with: the last chosen set, or the book or
    /// shelf showing now.
    private var chosenForSheet: [UUID] {
        let stored = FeedModeChoice.bookIDs(from: chosenBookIDs)
        if modeRaw == "books", !stored.isEmpty { return stored }
        switch app.feed.mode {
        case let .single(id): return [id]
        case let .shelf(shelf): return shelf.bookIDs
        case .mix, .readingList: return []
        }
    }

    private func chooseBooks(_ ids: [UUID]) {
        focusShelfID = ""
        chosenBookIDs = FeedModeChoice.storage(ids)
        if ids.count == 1 {
            singleBookID = ids[0].uuidString
            modeRaw = "single"
        } else {
            modeRaw = ids.isEmpty ? "mix" : "books"
        }
    }

    private func saveShelf(_ name: String, _ ids: [UUID]) {
        guard let id = app.shelves.create(name: name, bookIDs: ids) else { return }
        focusShelfID = ""
        feedShelfID = id.uuidString
        modeRaw = "shelf"
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
