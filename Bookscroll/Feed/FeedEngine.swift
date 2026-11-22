import Foundation

enum FeedMode: Equatable, Sendable {
    /// Interleave all books at random. Each book continues from its own position.
    case mix
    /// Go straight through one book.
    case single(UUID)
    /// Interleave the books of one shelf, like Mix. Mix filters (hidden, snoozed, finished)
    /// do not apply: the shelf is the reader's own choice.
    case shelf(ShelfSelection)

    /// Mix and shelf mode interleave books; One book mode does not.
    var interleaves: Bool {
        if case .single = self { return false }
        return true
    }
}

/// The shelf a shelf-mode feed shows.
struct ShelfSelection: Equatable, Sendable {
    let id: UUID
    let name: String
    let bookIDs: [UUID]
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
    /// The post comes from Mix mode or Saved, where posts of different books or places sit
    /// together (tapping the post opens it in context).
    var showsThreadButton: Bool
    /// Part number (1-based) when a long segment was split by the word limit.
    let part: Int
    let partCount: Int
    /// The first post of a chapter: the post shows a "New chapter" line.
    var startsChapter: Bool

    static func makeID(bookID: UUID, style: PostStyle, index: Int, part: Int = 1, partCount: Int = 1) -> String {
        let base = "\(bookID.uuidString)|\(style.rawValue)|\(index)"
        return partCount > 1 ? "\(base)|\(part)/\(partCount)" : base
    }

    /// `segment` is the stored segment, or one part of it (same index, a sub-range of the text).
    init(segment: SegmentRecord, book: FeedBook, showsThreadButton: Bool, part: Int = 1, partCount: Int = 1) {
        self.id = FeedPost.makeID(bookID: segment.bookID, style: segment.style, index: segment.index, part: part, partCount: partCount)
        self.bookID = segment.bookID
        self.bookTitle = book.title
        self.bookAuthor = book.author
        self.bookTotalCharacters = book.totalCharacters
        self.segment = segment
        self.chapterHeader = nil
        self.continuesThread = false
        self.threadContinuesBelow = false
        self.showsThreadButton = showsThreadButton
        self.part = part
        self.partCount = partCount
        self.startsChapter = false
    }

    var percent: Int { TextUtils.percent(segment.charStart, of: bookTotalCharacters) }

    /// "Chapter 3 · 42%", or "42%" when the book has no chapter labels, then "· 1/3" for parts.
    /// The grey line under the title: the chapter, the percent only on the first post of a
    /// chapter, and the part number of a split paragraph. Empty when there is nothing to show.
    var progressLine: String {
        line(showingPercent: startsChapter)
    }

    /// The chapter, the percent and the part number, always (context peek).
    var fullProgressLine: String {
        line(showingPercent: true)
    }

    private func line(showingPercent: Bool) -> String {
        var parts: [String] = []
        if !segment.chapter.isEmpty { parts.append(segment.chapter) }
        if showingPercent { parts.append("\(percent)%") }
        if partCount > 1 { parts.append("\(part)/\(partCount)") }
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// A segment to show: the whole segment, or one part of it.
struct PostPiece: Equatable {
    let segment: SegmentRecord
    let part: Int
    let partCount: Int

    /// Splits a segment by the word limit. Each part keeps the segment's index and chapter;
    /// the last part's range runs to the segment's end, so the parts tile the segment.
    static func pieces(of segment: SegmentRecord, limit: Int?, splitter: SentenceSplitter) -> [PostPiece] {
        guard let limit else { return [PostPiece(segment: segment, part: 1, partCount: 1)] }
        let ranges = PostSplitter.parts(of: segment.text, limit: limit, splitter: splitter)
        guard ranges.count > 1 else { return [PostPiece(segment: segment, part: 1, partCount: 1)] }
        let text = segment.text as NSString
        return ranges.enumerated().map { n, range in
            let isLast = n == ranges.count - 1
            let part = SegmentRecord(
                bookID: segment.bookID,
                style: segment.style,
                index: segment.index,
                charStart: segment.charStart + range.lowerBound,
                charEnd: isLast ? segment.charEnd : segment.charStart + range.upperBound,
                chapter: segment.chapter,
                text: text.substring(with: NSRange(range)).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return PostPiece(segment: part, part: n + 1, partCount: ranges.count)
        }
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
/// - With a word limit, a long segment becomes parts of at most that many words; parts tile
///   the segment, so positions resume inside a segment at the right part.
/// - Mix leaves out hidden and snoozed books and picks books in proportion to their weight.
final class FeedEngine {
    static let fetchBatchSize = 20
    static let pageSize = 30

    let style: PostStyle
    let mode: FeedMode
    let wordLimit: WordLimit
    private(set) var books: [UUID: FeedBook] = [:]
    private var bookOrder: [UUID] = []
    private(set) var posts: [FeedPost] = []
    private(set) var isAtEnd = false
    private(set) var shownIDs: Set<String> = []

    private let source: SegmentSource
    private let now: () -> Date
    private var rng: SeededGenerator
    private let splitter = SentenceSplitter()
    private var nextIndex: [UUID: Int] = [:]
    private var buffers: [UUID: [PostPiece]] = [:]
    private var exhausted: Set<UUID> = []
    /// End offset of the furthest post shown per book in this session.
    private var lastShownEnd: [UUID: Int] = [:]
    /// Parts that end at or before this offset are skipped (resuming inside a segment).
    private var skipBefore: [UUID: Int] = [:]
    /// Chapter of the segment before the next one to emit, per book.
    private var previousChapter: [UUID: String] = [:]
    private var emittedIDs: Set<String> = []
    private var positionByID: [String: Int] = [:]
    private var shownPrefix = 0
    private var leadingBook: UUID?

    init(
        source: SegmentSource,
        books: [FeedBook],
        style: PostStyle,
        mode: FeedMode,
        seed: UInt64,
        wordLimit: WordLimit = .off,
        now: @escaping () -> Date = { Date() }
    ) {
        self.source = source
        self.style = style
        self.mode = mode
        self.wordLimit = wordLimit
        self.now = now
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
            guard let piece = nextPiece(for: bookID) else {
                exhausted.insert(bookID)
                continue
            }
            let id = FeedPost.makeID(bookID: bookID, style: piece.segment.style, index: piece.segment.index, part: piece.part, partCount: piece.partCount)
            if emittedIDs.contains(id) { continue }
            append(piece)
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
            lastShownEnd[bookID] = max(lastShownEnd[bookID] ?? 0, post.segment.charEnd)
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
        skipBefore = [:]
        previousChapter = [:]
        exhausted = []
        emittedIDs = shownIDs
        isAtEnd = false
        self.leadingBook = leadingBook
        loadMore()
    }

    /// Moves a book to `offset` on an explicit request ("Continue in feed from here", "Jump to").
    /// The book's posts may then be shown again.
    func resetBook(_ bookID: UUID, offset: Int) {
        guard var book = books[bookID] else { return }
        book.positionOffset = offset
        books[bookID] = book
        lastShownEnd[bookID] = nil
        let prefix = bookID.uuidString + "|"
        shownIDs = shownIDs.filter { !$0.hasPrefix(prefix) }
    }

    /// Applies library changes: removes deleted books, adds new ones, and takes the new feed
    /// settings (hide, snooze, weight) of existing books. Unseen posts of books that Mix now
    /// leaves out are removed; posts already shown stay. Keeps session state.
    func updateBooks(_ newBooks: [FeedBook]) {
        let newIDs = Set(newBooks.map(\.id))
        let removed = Set(bookOrder).subtracting(newIDs)
        for id in removed {
            books[id] = nil
            nextIndex[id] = nil
            buffers[id] = nil
            exhausted.remove(id)
            lastShownEnd[id] = nil
            skipBefore[id] = nil
            previousChapter[id] = nil
        }
        bookOrder.removeAll { removed.contains($0) }
        for book in newBooks {
            if let current = books[book.id] {
                // New details, Mix settings and finish date; the feed keeps its own place.
                var updated = book
                updated.positionOffset = current.positionOffset
                books[book.id] = updated
            } else {
                books[book.id] = book
                bookOrder.append(book.id)
                isAtEnd = false
            }
        }
        let active = Set(activeBooks())
        let before = posts.count
        posts = posts.enumerated().filter { n, post in
            guard !removed.contains(post.bookID) else { return false }
            return active.contains(post.bookID) || n < shownPrefix || shownIDs.contains(post.id)
        }.map(\.element)
        if posts.count != before {
            // A removed post can break a thread; keep a line only where the next post continues it.
            for n in posts.indices {
                posts[n].threadContinuesBelow = n + 1 < posts.count
                    && posts[n + 1].continuesThread
                    && posts[n + 1].bookID == posts[n].bookID
            }
            rebuildPostIndex()
        }
    }

    // MARK: - Private

    private func activeBooks() -> [UUID] {
        switch mode {
        case .mix:
            let date = now()
            return bookOrder.filter { books[$0]?.isExcludedFromMix(now: date) == false }
        case let .single(id):
            return books[id] == nil ? [] : [id]
        case let .shelf(shelf):
            let ids = Set(shelf.bookIDs)
            return bookOrder.filter { ids.contains($0) }
        }
    }

    /// Random book, weighted by `feedWeight` (Mix). One book mode has one candidate.
    private func pickBook() -> UUID? {
        let candidates = activeBooks().filter { !exhausted.contains($0) }
        guard !candidates.isEmpty else { return nil }
        if let leading = leadingBook {
            leadingBook = nil
            if candidates.contains(leading) { return leading }
        }
        if candidates.count == 1 { return candidates[0] }
        let weights = candidates.map { min(max(books[$0]?.feedWeight ?? 1, 0.1), 10) }
        let total = weights.reduce(0, +)
        var target = Double.random(in: 0..<total, using: &rng)
        for (candidate, weight) in zip(candidates, weights) {
            if target < weight { return candidate }
            target -= weight
        }
        return candidates[candidates.count - 1]
    }

    /// Where a book continues: after the furthest post shown in this session, or at its
    /// saved position. Sets the skip offset and the chapter of the segment before.
    private func startIndex(for bookID: UUID) -> Int? {
        guard let book = books[bookID] else { return nil }
        let bookStyle = style(for: bookID)
        let offset = lastShownEnd[bookID] ?? book.positionOffset
        if lastShownEnd[bookID] != nil && offset >= book.totalCharacters { return nil }
        let index = source.indexContaining(offset: offset, book: book, style: bookStyle) ?? 0
        skipBefore[bookID] = offset
        if index > 0, let before = source.segments(book: book, style: bookStyle, from: index - 1, limit: 1).first {
            previousChapter[bookID] = before.chapter
        }
        return index
    }

    private func nextPiece(for bookID: UUID) -> PostPiece? {
        guard let book = books[bookID] else { return nil }
        let bookStyle = style(for: bookID)
        let limit = wordLimit.limit(for: book)
        while buffers[bookID, default: []].isEmpty {
            let start: Int
            if let next = nextIndex[bookID] {
                start = next
            } else if let first = startIndex(for: bookID) {
                start = first
            } else {
                return nil
            }
            guard start < book.segmentCount(bookStyle) else { return nil }
            let batch = source.segments(book: book, style: bookStyle, from: start, limit: FeedEngine.fetchBatchSize)
            guard let last = batch.last else { return nil }
            nextIndex[bookID] = last.index + 1
            let skip = skipBefore[bookID] ?? 0
            skipBefore[bookID] = nil
            buffers[bookID] = batch
                .flatMap { PostPiece.pieces(of: $0, limit: limit, splitter: splitter) }
                .filter { $0.segment.charEnd > skip }
        }
        guard var buffer = buffers[bookID], !buffer.isEmpty else { return nil }
        let piece = buffer.removeFirst()
        buffers[bookID] = buffer
        return piece
    }

    private func append(_ piece: PostPiece) {
        let segment = piece.segment
        guard let book = books[segment.bookID] else { return }
        var post = FeedPost(segment: segment, book: book, showsThreadButton: mode.interleaves, part: piece.part, partCount: piece.partCount)
        let previous = previousChapter[segment.bookID]
        if piece.part == 1 {
            post.startsChapter = !segment.chapter.isEmpty && segment.chapter != previous
                && (previous != nil || segment.index == 0)
        }
        previousChapter[segment.bookID] = segment.chapter
        if case .single = mode {
            if let lastIndex = posts.indices.last,
               posts[lastIndex].bookID == segment.bookID,
               posts[lastIndex].segment.charEnd == segment.charStart,
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
