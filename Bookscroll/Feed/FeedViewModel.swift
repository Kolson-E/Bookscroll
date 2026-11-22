import Foundation
import Observation

@MainActor
@Observable
final class FeedViewModel {
    private let store: LibraryStore
    @ObservationIgnored private var engine: FeedEngine?
    @ObservationIgnored private var configured = false

    private(set) var posts: [FeedPost] = []
    private(set) var isAtEnd = false
    private(set) var books: [FeedBook] = []
    private(set) var style: PostStyle = .paragraph
    private(set) var mode: FeedMode = .mix
    private(set) var wordLimit: WordLimit = .off
    /// Book of the top post in Mix, so Mix opens on the same post after a mode switch or a
    /// relaunch.
    @ObservationIgnored private let defaults: UserDefaults
    static let mixTopBookKey = "mixTopBookID"
    /// Called with the characters the feed moved past in each book (reading stats, Live
    /// Activity).
    @ObservationIgnored var onRead: (([UUID: Int]) -> Void)?
    /// Top visible post, bound to the scroll view.
    var scrolledID: String?

    init(store: LibraryStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
    }

    var title: String {
        switch mode {
        case let .single(id):
            return books.first { $0.id == id }?.title ?? "Feed"
        case let .shelf(shelf):
            return shelf.name
        case .mix:
            return "Feed"
        }
    }

    func configure(style: PostStyle, mode: FeedMode, wordLimit: WordLimit = .off) {
        if configured && style == self.style && mode == self.mode && wordLimit == self.wordLimit { return }
        configured = true
        self.style = style
        self.mode = mode
        self.wordLimit = wordLimit
        rebuild()
    }

    func loadMore() {
        guard let engine, !engine.isAtEnd else { return }
        engine.loadMore()
        sync()
    }

    func postAppeared(_ id: String) {
        guard let engine, let index = engine.index(ofPost: id) else { return }
        if index >= engine.posts.count - 8 { loadMore() }
    }

    /// Called when the top visible post changes. That post and all posts above it count as shown.
    func didScroll(to id: String?) {
        guard let id, let engine else { return }
        if mode == .mix, let post = engine.index(ofPost: id).map({ engine.posts[$0] }) {
            defaults.set(post.bookID.uuidString, forKey: Self.mixTopBookKey)
        }
        let updates = engine.markShown(through: id)
        var read: [UUID: Int] = [:]
        for (bookID, offset) in updates {
            let before = store.book(id: bookID)?.positionOffset ?? offset
            store.setPosition(bookID: bookID, offset: offset)
            if offset > before { read[bookID, default: 0] += offset - before }
        }
        if !read.isEmpty { onRead?(read) }
        if !updates.isEmpty { store.saveIfDue() }
        if let index = engine.index(ofPost: id), index >= engine.posts.count - 12 {
            loadMore()
        }
    }

    func refresh() {
        guard let engine else { return }
        engine.refresh(seed: UInt64.random(in: .min ... .max))
        sync()
        scrolledID = posts.first?.id
    }

    /// Picks up imported or deleted books.
    func reloadBooks() {
        let latest = store.feedBooks()
        guard let engine else {
            if configured { rebuild() }
            return
        }
        if case let .single(id) = mode, !latest.contains(where: { $0.id == id }) {
            mode = .mix
            rebuild()
            return
        }
        engine.updateBooks(latest)
        books = latest
        if engine.posts.count < FeedEngine.pageSize { engine.loadMore() }
        sync()
    }

    /// Takes a book out of the feed right away (before it is deleted).
    func removeBook(_ id: UUID) {
        guard let engine else { return }
        let remaining = books.filter { $0.id != id }
        if case let .single(selected) = mode, selected == id {
            books = remaining
            mode = .mix
            rebuild(excluding: id)
            return
        }
        engine.updateBooks(remaining)
        books = remaining
        sync()
    }

    /// "Continue in feed from here": move the book to `offset` and show the feed from there.
    func jump(bookID: UUID, offset: Int) {
        store.setPosition(bookID: bookID, offset: offset)
        store.save()
        if engine == nil { rebuild() }
        guard let engine else { return }
        engine.resetBook(bookID, offset: offset)
        engine.refresh(seed: UInt64.random(in: .min ... .max), leadingBook: bookID)
        sync()
        scrolledID = posts.first?.id
    }

    /// Starts the feed again from the places stored in the library (after a restore).
    func reloadFromLibrary() {
        guard configured else { return }
        rebuild()
    }

    private func rebuild(excluding excluded: UUID? = nil) {
        books = store.feedBooks().filter { $0.id != excluded }
        if case let .single(id) = mode, !books.contains(where: { $0.id == id }) {
            mode = .mix
        }
        let engine = FeedEngine(
            source: store,
            books: books,
            style: style,
            mode: mode,
            seed: UInt64.random(in: .min ... .max),
            wordLimit: wordLimit
        )
        if mode == .mix, let id = defaults.string(forKey: Self.mixTopBookKey).flatMap(UUID.init(uuidString:)) {
            engine.refresh(seed: UInt64.random(in: .min ... .max), leadingBook: id)
        } else {
            engine.loadMore()
        }
        self.engine = engine
        sync()
        scrolledID = posts.first?.id
    }

    private func sync() {
        guard let engine else { return }
        posts = engine.posts
        isAtEnd = engine.isAtEnd
    }
}
