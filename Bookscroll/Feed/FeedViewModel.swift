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
    /// Top visible post, bound to the scroll view.
    var scrolledID: String?

    init(store: LibraryStore) {
        self.store = store
    }

    var title: String {
        if case let .single(id) = mode, let book = books.first(where: { $0.id == id }) {
            return book.title
        }
        return "Feed"
    }

    func configure(style: PostStyle, mode: FeedMode) {
        if configured && style == self.style && mode == self.mode { return }
        configured = true
        self.style = style
        self.mode = mode
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
        let updates = engine.markShown(through: id)
        for (bookID, offset) in updates {
            store.setPosition(bookID: bookID, offset: offset)
        }
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

    /// "Continue in feed from here": move the book to `offset` and show the feed from there.
    func jump(bookID: UUID, offset: Int) {
        store.setPosition(bookID: bookID, offset: offset)
        if engine == nil { rebuild() }
        guard let engine else { return }
        engine.resetBook(bookID, offset: offset)
        engine.refresh(seed: UInt64.random(in: .min ... .max), leadingBook: bookID)
        sync()
        scrolledID = posts.first?.id
    }

    private func rebuild() {
        books = store.feedBooks()
        if case let .single(id) = mode, !books.contains(where: { $0.id == id }) {
            mode = .mix
        }
        let engine = FeedEngine(
            source: store,
            books: books,
            style: style,
            mode: mode,
            seed: UInt64.random(in: .min ... .max)
        )
        engine.loadMore()
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
