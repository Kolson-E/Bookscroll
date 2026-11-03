import Foundation

enum FeedMode: Equatable, Sendable {
    /// Interleave all books at random. Each book continues from its own position.
    case mix
    /// Go straight through one book.
    case single(UUID)
}

/// One post in the timeline.
struct FeedPost: Identifiable, Equatable {
    let id: String
    let bookID: UUID
    let bookTitle: String
    let bookAuthor: String
    let bookTotalCharacters: Int
    let segment: SegmentRecord
    /// Set on the first post of a chapter in One book mode.
    var chapterHeader: String?
    /// This post joins the previous post in a thread (One book mode).
    var continuesThread: Bool
    /// The next post joins this one in a thread (One book mode).
    var threadContinuesBelow: Bool
    /// "Show thread" link (Mix mode and Saved).
    var showsThreadButton: Bool

    static func makeID(bookID: UUID, style: PostStyle, index: Int) -> String {
        "\(bookID.uuidString)|\(style.rawValue)|\(index)"
    }

    init(segment: SegmentRecord, book: FeedBook, showsThreadButton: Bool) {
        self.id = FeedPost.makeID(bookID: segment.bookID, style: segment.style, index: segment.index)
        self.bookID = segment.bookID
        self.bookTitle = book.title
        self.bookAuthor = book.author
        self.bookTotalCharacters = book.totalCharacters
        self.segment = segment
        self.chapterHeader = nil
        self.continuesThread = false
        self.threadContinuesBelow = false
        self.showsThreadButton = showsThreadButton
    }

    var percent: Int { TextUtils.percent(segment.charStart, of: bookTotalCharacters) }

    /// "Chapter 3 · 42%", or "42%" when the book has no chapter labels.
    var progressLine: String {
        segment.chapter.isEmpty ? "\(percent)%" : "\(segment.chapter) \u{00B7} \(percent)%"
    }
}

/// SplitMix64. Deterministic, so tests can fix the shuffle.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds the timeline. Pure logic over a `SegmentSource`; it holds no UI state.
///
/// Guarantees within one session (one engine):
/// - A post is never shown twice and the list never holds a post twice.
/// - A book's position changes only through `markShown`, which is called for posts that
///   were actually on screen.
/// - Segments are fetched in small batches by (book, style, index); the engine never loads
///   a whole book.
final class FeedEngine {
    static let fetchBatchSize = 20
    static let pageSize = 30

    let style: PostStyle
    let mode: FeedMode
    private(set) var books: [UUID: FeedBook] = [:]
    private var bookOrder: [UUID] = []
    private(set) var posts: [FeedPost] = []
    private(set) var isAtEnd = false
    private(set) var shownIDs: Set<String> = []

    private let source: SegmentSource
    private var rng: SeededGenerator
    private var nextIndex: [UUID: Int] = [:]
    private var buffers: [UUID: [SegmentRecord]] = [:]
    private var exhausted: Set<UUID> = []
    private var lastShownIndex: [UUID: Int] = [:]
    private var emittedIDs: Set<String> = []
    private var positionByID: [String: Int] = [:]
    private var shownPrefix = 0
    private var leadingBook: UUID?

    init(source: SegmentSource, books: [FeedBook], style: PostStyle, mode: FeedMode, seed: UInt64) {
        self.source = source
        self.style = style
        self.mode = mode
        self.rng = SeededGenerator(seed: seed)
        for book in books {
            self.books[book.id] = book
            bookOrder.append(book.id)
        }
    }

    func style(for bookID: UUID) -> PostStyle {
        books[bookID]?.effectiveStyle(style) ?? style
    }

    func index(ofPost id: String) -> Int? {
        positionByID[id]
    }

    /// Appends up to `count` posts. Sets `isAtEnd` when every active book is exhausted.
    func loadMore(_ count: Int = FeedEngine.pageSize) {
        var added = 0
        while added < count {
            guard let bookID = pickBook() else {
                isAtEnd = true
                break
            }
            guard let segment = nextSegment(for: bookID) else {
                exhausted.insert(bookID)
                continue
            }
            let id = FeedPost.makeID(bookID: bookID, style: segment.style, index: segment.index)
            if emittedIDs.contains(id) { continue }
            append(segment)
            added += 1
        }
    }

    /// Marks the post with `id` and every post above it as shown. Returns the new positions
    /// of the books whose position moved forward.
    @discardableResult
    func markShown(through id: String) -> [UUID: Int] {
        guard let last = positionByID[id], last >= shownPrefix else { return [:] }
        var updates: [UUID: Int] = [:]
        for i in shownPrefix...last {
            let post = posts[i]
            guard shownIDs.insert(post.id).inserted else { continue }
            let bookID = post.bookID
            lastShownIndex[bookID] = max(lastShownIndex[bookID] ?? -1, post.segment.index)
            if var book = books[bookID], post.segment.charStart > book.positionOffset {
                book.positionOffset = post.segment.charStart
                books[bookID] = book
                updates[bookID] = book.positionOffset
            }
        }
        shownPrefix = last + 1
        return updates
    }

    /// Rebuilds the list. Mix mode gets a new shuffle. Posts already shown in this session
    /// are never loaded again; loaded but unseen posts can come back.
    func refresh(seed: UInt64, leadingBook: UUID? = nil) {
        rng = SeededGenerator(seed: seed)
        posts = []
        positionByID = [:]
        shownPrefix = 0
        buffers = [:]
        nextIndex = [:]
        exhausted = []
        emittedIDs = shownIDs
        isAtEnd = false
        self.leadingBook = leadingBook
        loadMore()
    }

    /// Moves a book to `offset` on an explicit request ("Continue in feed from here").
    /// The book's posts may then be shown again.
    func resetBook(_ bookID: UUID, offset: Int) {
        guard var book = books[bookID] else { return }
        book.positionOffset = offset
        books[bookID] = book
        lastShownIndex[bookID] = nil
        let prefix = bookID.uuidString + "|"
        shownIDs = shownIDs.filter { !$0.hasPrefix(prefix) }
    }

    /// Applies library changes: removes deleted books, adds new ones, keeps session state.
    func updateBooks(_ newBooks: [FeedBook]) {
        let newIDs = Set(newBooks.map(\.id))
        let removed = Set(bookOrder).subtracting(newIDs)
        if !removed.isEmpty {
            for id in removed {
                books[id] = nil
                nextIndex[id] = nil
                buffers[id] = nil
                exhausted.remove(id)
                lastShownIndex[id] = nil
            }
            bookOrder.removeAll { removed.contains($0) }
            posts.removeAll { removed.contains($0.bookID) }
            rebuildPostIndex()
        }
        for book in newBooks where books[book.id] == nil {
            books[book.id] = book
            bookOrder.append(book.id)
            isAtEnd = false
        }
    }

    // MARK: - Private

    private func activeBooks() -> [UUID] {
        switch mode {
        case .mix:
            return bookOrder
        case let .single(id):
            return books[id] == nil ? [] : [id]
        }
    }

    private func pickBook() -> UUID? {
        let candidates = activeBooks().filter { !exhausted.contains($0) }
        guard !candidates.isEmpty else { return nil }
        if let leading = leadingBook {
            leadingBook = nil
            if candidates.contains(leading) { return leading }
        }
        if candidates.count == 1 { return candidates[0] }
        return candidates.randomElement(using: &rng)
    }

    private func startIndex(for bookID: UUID) -> Int {
        if let shown = lastShownIndex[bookID] { return shown + 1 }
        guard let book = books[bookID] else { return 0 }
        return source.indexContaining(offset: book.positionOffset, book: book, style: style(for: bookID)) ?? 0
    }

    private func nextSegment(for bookID: UUID) -> SegmentRecord? {
        guard let book = books[bookID] else { return nil }
        let bookStyle = style(for: bookID)
        if buffers[bookID, default: []].isEmpty {
            let start = nextIndex[bookID] ?? startIndex(for: bookID)
            guard start < book.segmentCount(bookStyle) else { return nil }
            let batch = source.segments(book: book, style: bookStyle, from: start, limit: FeedEngine.fetchBatchSize)
            guard let last = batch.last else { return nil }
            nextIndex[bookID] = last.index + 1
            buffers[bookID] = batch
        }
        guard var buffer = buffers[bookID], !buffer.isEmpty else { return nil }
        let segment = buffer.removeFirst()
        buffers[bookID] = buffer
        return segment
    }

    private func append(_ segment: SegmentRecord) {
        guard let book = books[segment.bookID] else { return }
        var post = FeedPost(segment: segment, book: book, showsThreadButton: mode == .mix)
        if case .single = mode {
            if let lastIndex = posts.indices.last,
               posts[lastIndex].bookID == segment.bookID,
               posts[lastIndex].segment.index + 1 == segment.index,
               posts[lastIndex].segment.chapter == segment.chapter {
                post.continuesThread = true
                posts[lastIndex].threadContinuesBelow = true
            } else if !segment.chapter.isEmpty {
                post.chapterHeader = segment.chapter
            }
        }
        emittedIDs.insert(post.id)
        positionByID[post.id] = posts.count
        posts.append(post)
    }

    private func rebuildPostIndex() {
        positionByID = [:]
        for (i, post) in posts.enumerated() { positionByID[post.id] = i }
        shownPrefix = 0
        while shownPrefix < posts.count, shownIDs.contains(posts[shownPrefix].id) { shownPrefix += 1 }
    }
}
