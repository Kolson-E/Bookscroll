import Foundation
import SwiftData

/// Where the feed engine gets its segments. The SwiftData store and the test fixtures conform.
protocol SegmentSource: AnyObject {
    /// Up to `limit` segments of a book and style, starting at `index`, in order.
    func segments(book: FeedBook, style: PostStyle, from index: Int, limit: Int) -> [SegmentRecord]
    /// Index of the segment whose range contains `offset`.
    func indexContaining(offset: Int, book: FeedBook, style: PostStyle) -> Int?
}

/// All SwiftData access for the UI. Every query is bounded by a fetch limit and uses the
/// indexed segment keys, so no query loads all segments of a book.
final class LibraryStore: SegmentSource {
    let context: ModelContext
    private var bookCache: [UUID: Book] = [:]

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Books

    /// Books in the library, newest first. Books being deleted are left out.
    func allBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.deletionPending == false },
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        let books = (try? context.fetch(descriptor)) ?? []
        for book in books { bookCache[book.id] = book }
        return books
    }

    func feedBooks() -> [FeedBook] {
        allBooks().map(FeedBook.init)
    }

    func book(id: UUID) -> Book? {
        if let cached = bookCache[id], cached.modelContext != nil { return cached }
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let book = try? context.fetch(descriptor).first
        bookCache[id] = book
        return book
    }

    func feedBook(id: UUID) -> FeedBook? {
        book(id: id).map(FeedBook.init)
    }

    func setPosition(bookID: UUID, offset: Int) {
        guard let book = book(id: bookID) else { return }
        let clamped = min(max(0, offset), max(0, book.totalCharacters - 1))
        if book.positionOffset != clamped {
            book.positionOffset = clamped
        }
    }

    /// Deletes a book with all its segments and marks, on this context.
    func deleteBook(id: UUID) throws {
        save()
        try BookDeleter.delete(bookID: id, in: context)
        bookCache[id] = nil
    }

    /// Hides a book at once. `BookDeleter` then removes its rows.
    func markForDeletion(id: UUID) {
        guard let book = book(id: id) else { return }
        book.deletionPending = true
        save()
    }

    /// Drops the cached object for a book deleted through another context.
    func forgetBook(id: UUID) {
        bookCache[id] = nil
    }

    private var lastSave = Date.distantPast

    func save() {
        lastSave = .now
        guard context.hasChanges else { return }
        try? context.save()
    }

    /// Saves at most every `interval` seconds. Used while scrolling, so a crash or a forced
    /// quit loses at most a few seconds of reading position.
    func saveIfDue(interval: TimeInterval = 5, now: Date = .now) {
        guard now.timeIntervalSince(lastSave) >= interval else { return }
        save()
        lastSave = now
    }

    // MARK: Segments

    func segments(book: FeedBook, style: PostStyle, from index: Int, limit: Int) -> [SegmentRecord] {
        guard index >= 0, limit > 0 else { return [] }
        let lower = SegmentKey.make(ordinal: book.ordinal, style: style, value: index)
        let upper = SegmentKey.upperBound(ordinal: book.ordinal, style: style)
        var descriptor = FetchDescriptor<Segment>(
            predicate: #Predicate { $0.indexKey >= lower && $0.indexKey < upper },
            sortBy: [SortDescriptor(\.indexKey)]
        )
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(SegmentRecord.init)
    }

    /// Segments before `index` (exclusive), oldest first.
    func segments(book: FeedBook, style: PostStyle, before index: Int, limit: Int) -> [SegmentRecord] {
        guard index > 0, limit > 0 else { return [] }
        let lower = SegmentKey.lowerBound(ordinal: book.ordinal, style: style)
        let upper = SegmentKey.make(ordinal: book.ordinal, style: style, value: index)
        var descriptor = FetchDescriptor<Segment>(
            predicate: #Predicate { $0.indexKey >= lower && $0.indexKey < upper },
            sortBy: [SortDescriptor(\.indexKey, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(SegmentRecord.init).reversed()
    }

    func indexContaining(offset: Int, book: FeedBook, style: PostStyle) -> Int? {
        let lower = SegmentKey.lowerBound(ordinal: book.ordinal, style: style)
        let target = SegmentKey.make(ordinal: book.ordinal, style: style, value: max(0, offset))
        var descriptor = FetchDescriptor<Segment>(
            predicate: #Predicate { $0.offsetKey >= lower && $0.offsetKey <= target },
            sortBy: [SortDescriptor(\.offsetKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first)?.index
    }

    /// Segments whose ranges overlap `start..<end`, in order.
    func segmentsOverlapping(start: Int, end: Int, book: FeedBook, style: PostStyle, limit: Int = 64) -> [SegmentRecord] {
        guard let first = indexContaining(offset: start, book: book, style: style) else { return [] }
        return segments(book: book, style: style, from: first, limit: limit)
            .filter { $0.charStart < end && start < $0.charEnd }
    }

    // MARK: Marks

    func allMarks() -> [MarkRecord] {
        let descriptor = FetchDescriptor<Mark>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map(MarkRecord.init)
    }

    @discardableResult
    func addMark(kind: MarkKind, bookID: UUID, charStart: Int, charEnd: Int) -> MarkRecord? {
        guard let book = book(id: bookID) else { return nil }
        let mark = Mark(bookID: bookID, kind: kind, charStart: charStart, charEnd: charEnd)
        context.insert(mark)
        mark.book = book
        try? context.save()
        return MarkRecord(mark)
    }

    func deleteMarks(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let descriptor = FetchDescriptor<Mark>(predicate: #Predicate { ids.contains($0.id) })
        for mark in (try? context.fetch(descriptor)) ?? [] {
            context.delete(mark)
        }
        try? context.save()
    }
}

/// Deletes a book, its marks and its segments. The book is already hidden (`deletionPending`),
/// so a book with part of its segments is never shown. Segments go first, by key range in
/// the store; the book row goes last, and the cascade rule removes anything left. A deletion
/// that did not finish (the app stopped) runs again at the next launch.
enum BookDeleter {
    static let defaultChunkSize = 2000

    static func delete(bookID: UUID, in context: ModelContext, chunkSize: Int = defaultChunkSize) throws {
        var bookDescriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookID })
        bookDescriptor.fetchLimit = 1
        if let ordinal = try context.fetch(bookDescriptor).first?.ordinal {
            // Fast path: remove the segments in the store by key range, without loading them.
            // If the store refuses, the cascade below removes them instead.
            let lower = SegmentKey.lowerBound(ordinal: ordinal, style: .paragraph)
            let upper = SegmentKey.lowerBound(ordinal: ordinal + 1, style: .paragraph)
            do {
                try context.delete(model: Segment.self, where: #Predicate { $0.indexKey >= lower && $0.indexKey < upper })
                try context.save()
            } catch {
                context.rollback()
            }
        }
        if let book = try context.fetch(bookDescriptor).first {
            context.delete(book)
            try context.save()
        }

        // Rows without a book link (not written by this version of the app) go in bounded chunks.
        for model in [0, 1] {
            while true {
                let chunk: [any PersistentModel]
                if model == 0 {
                    var descriptor = FetchDescriptor<Mark>(predicate: #Predicate { $0.bookID == bookID })
                    descriptor.fetchLimit = max(1, chunkSize)
                    chunk = try context.fetch(descriptor)
                } else {
                    var descriptor = FetchDescriptor<Segment>(predicate: #Predicate { $0.bookID == bookID })
                    descriptor.fetchLimit = max(1, chunkSize)
                    chunk = try context.fetch(descriptor)
                }
                if chunk.isEmpty { break }
                for item in chunk { context.delete(item) }
                try context.save()
            }
        }
    }

    /// Ids of books whose deletion was started but not finished.
    static func pendingBookIDs(in context: ModelContext) -> [UUID] {
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.deletionPending == true })
        return ((try? context.fetch(descriptor)) ?? []).map(\.id)
    }
}

/// In-memory view of all marks, grouped by book, for fast overlap checks while scrolling.
struct MarkIndex: Equatable {
    private var byBook: [UUID: [MarkRecord]] = [:]

    init(_ marks: [MarkRecord] = []) {
        for mark in marks { byBook[mark.bookID, default: []].append(mark) }
    }

    var all: [MarkRecord] {
        byBook.values.flatMap { $0 }.sorted { $0.createdAt > $1.createdAt }
    }

    var count: Int { byBook.values.reduce(0) { $0 + $1.count } }

    /// A post is marked when its range overlaps any mark of that kind in the same book.
    func isMarked(_ kind: MarkKind, bookID: UUID, start: Int, end: Int) -> Bool {
        byBook[bookID]?.contains { $0.kind == kind && $0.overlaps(start: start, end: end) } ?? false
    }

    func overlapping(_ kind: MarkKind, bookID: UUID, start: Int, end: Int) -> [MarkRecord] {
        byBook[bookID]?.filter { $0.kind == kind && $0.overlaps(start: start, end: end) } ?? []
    }

    mutating func insert(_ mark: MarkRecord) {
        byBook[mark.bookID, default: []].append(mark)
    }

    mutating func remove(ids: Set<UUID>) {
        for key in byBook.keys {
            byBook[key]?.removeAll { ids.contains($0.id) }
        }
    }

    mutating func removeBook(_ bookID: UUID) {
        byBook[bookID] = nil
    }
}
