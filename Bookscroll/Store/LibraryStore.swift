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

    func allBooks() -> [Book] {
        let descriptor = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
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

    /// Deletes a book with all its segments and marks.
    func deleteBook(id: UUID) throws {
        try context.delete(model: Segment.self, where: #Predicate { $0.bookID == id })
        try context.delete(model: Mark.self, where: #Predicate { $0.bookID == id })
        if let book = book(id: id) {
            context.delete(book)
        }
        bookCache[id] = nil
        try context.save()
    }

    func save() {
        guard context.hasChanges else { return }
        try? context.save()
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
