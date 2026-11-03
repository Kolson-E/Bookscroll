import Foundation
import SQLite3
import SwiftData

/// Full-text index of every book's paragraphs, in its own SQLite file beside the library.
/// SwiftData has no full-text search; this index answers "where does this word appear"
/// without loading segments. It holds a copy of the paragraph text and can always be
/// rebuilt from the library (`indexMissingBooks`).
final class SearchIndex: @unchecked Sendable {
    struct Hit: Equatable, Sendable {
        let bookID: UUID
        /// Paragraph index (Paragraphs style).
        let index: Int
        /// Text around the match. Matched words are wrapped in `markStart` / `markEnd`.
        let snippet: String
    }

    static let markStart: Character = "\u{E000}"
    static let markEnd: Character = "\u{E001}"

    private var db: OpaquePointer?
    private let lock = NSLock()
    /// FTS5 when the system SQLite has it, otherwise FTS4.
    private(set) var usesFTS5 = true

    static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Search.sqlite")
    }

    /// Opens or creates the index file at `url`. The file is excluded from device backups:
    /// it only repeats text that the library already holds.
    convenience init(url: URL) throws {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(path: url.path)
        var fileURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? fileURL.setResourceValues(values)
    }

    /// An index that lives only in memory (tests, UI tests).
    static func inMemory() throws -> SearchIndex {
        try SearchIndex(path: ":memory:")
    }

    private init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw SearchIndexError.sqlite(message)
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("CREATE TABLE IF NOT EXISTS indexed_books (book TEXT PRIMARY KEY)")
        do {
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS paragraphs USING fts5(book UNINDEXED, idx UNINDEXED, body, tokenize = 'unicode61 remove_diacritics 2')")
        } catch {
            usesFTS5 = false
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS paragraphs USING fts4(book, idx, body, notindexed=book, notindexed=idx, tokenize=unicode61)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Writing

    /// Replaces the index entries of one book.
    func add(bookID: UUID, paragraphs: [SegmentRecord]) throws {
        try addBatch(bookID: bookID, paragraphs: paragraphs, first: true, last: true)
    }

    /// Adds paragraphs in parts. `first` clears the book's old entries; `last` marks it indexed.
    func addBatch(bookID: UUID, paragraphs: [SegmentRecord], first: Bool, last: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let book = bookID.uuidString
            if first {
                try run("DELETE FROM paragraphs WHERE book = ?", [.text(book)])
                try run("DELETE FROM indexed_books WHERE book = ?", [.text(book)])
            }
            let statement = try prepare("INSERT INTO paragraphs (book, idx, body) VALUES (?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            for paragraph in paragraphs where paragraph.style == .paragraph {
                sqlite3_reset(statement)
                bind(statement, [.text(book), .int(paragraph.index), .text(paragraph.text)])
                guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
            }
            if last {
                try run("INSERT OR REPLACE INTO indexed_books (book) VALUES (?)", [.text(book)])
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func remove(bookID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            try run("DELETE FROM paragraphs WHERE book = ?", [.text(bookID.uuidString)])
            try run("DELETE FROM indexed_books WHERE book = ?", [.text(bookID.uuidString)])
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func indexedBookIDs() -> Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = try? prepare("SELECT book FROM indexed_books") else { return [] }
        defer { sqlite3_finalize(statement) }
        var result = Set<UUID>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: text)) {
                result.insert(id)
            }
        }
        return result
    }

    /// Number of paragraphs held for a book.
    func entryCount(bookID: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = try? prepare("SELECT count(*) FROM paragraphs WHERE book = ?") else { return 0 }
        defer { sqlite3_finalize(statement) }
        bind(statement, [.text(bookID.uuidString)])
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    // MARK: Searching

    /// Turns what the user typed into a safe match expression: words only, lowercased (so
    /// AND, OR, NOT and NEAR are never operators), the last word as a prefix.
    static func matchExpression(for query: String) -> String? {
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.dropLast().joined(separator: " ") + (words.count > 1 ? " " : "") + words[words.count - 1] + "*"
    }

    /// Paragraphs that contain every word of `query` (the last word may be the start of a
    /// word). Best matches first with FTS5; book order with FTS4.
    func search(_ query: String, bookID: UUID? = nil, limit: Int = 50) -> [Hit] {
        guard let expression = Self.matchExpression(for: query), limit > 0 else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let start = String(Self.markStart)
        let end = String(Self.markEnd)
        let snippet = usesFTS5
            ? "snippet(paragraphs, 2, '\(start)', '\(end)', '\u{2026}', 16)"
            : "snippet(paragraphs, '\(start)', '\(end)', '\u{2026}', 2, 16)"
        var sql = "SELECT book, idx, \(snippet) FROM paragraphs WHERE paragraphs MATCH ?"
        var values: [Value] = [.text(expression)]
        if let bookID {
            sql += " AND book = ?"
            values.append(.text(bookID.uuidString))
        }
        sql += usesFTS5 ? " ORDER BY rank" : " ORDER BY book, CAST(idx AS INTEGER)"
        sql += " LIMIT \(limit)"
        guard let statement = try? prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(statement, values)
        var hits: [Hit] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bookText = sqlite3_column_text(statement, 0),
                  let id = UUID(uuidString: String(cString: bookText)) else { continue }
            let index = Int(sqlite3_column_int64(statement, 1))
            let text = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
            hits.append(Hit(bookID: id, index: index, snippet: text))
        }
        return hits
    }

    // MARK: Rebuilding

    /// Indexes every book in the library that the index does not hold yet (libraries from
    /// before the index existed, or an index file that was lost), and drops entries of books
    /// that are gone. Reads segments in bounded batches.
    func indexMissingBooks(container: ModelContainer, batchSize: Int = 2000) throws {
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.deletionPending == false }))
        let indexed = indexedBookIDs()
        let current = Set(books.map(\.id))
        for stale in indexed.subtracting(current) {
            try remove(bookID: stale)
        }
        for book in books where !indexed.contains(book.id) {
            let summary = FeedBook(book)
            var next = 0
            var first = true
            repeat {
                let lower = SegmentKey.make(ordinal: summary.ordinal, style: .paragraph, value: next)
                let upper = SegmentKey.upperBound(ordinal: summary.ordinal, style: .paragraph)
                var descriptor = FetchDescriptor<Segment>(
                    predicate: #Predicate { $0.indexKey >= lower && $0.indexKey < upper },
                    sortBy: [SortDescriptor(\.indexKey)]
                )
                descriptor.fetchLimit = batchSize
                let batch = try context.fetch(descriptor).map(SegmentRecord.init)
                let isLast = batch.count < batchSize
                try addBatch(bookID: summary.id, paragraphs: batch, first: first, last: isLast)
                first = false
                next = (batch.last?.index ?? next) + 1
                if isLast { break }
            } while true
        }
    }

    // MARK: SQLite helpers

    private enum Value {
        case text(String)
        case int(Int)
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw lastError() }
        return statement
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, values)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bind(_ statement: OpaquePointer?, _ values: [Value]) {
        for (offset, value) in values.enumerated() {
            let position = Int32(offset + 1)
            switch value {
            case let .text(text):
                sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case let .int(number):
                sqlite3_bind_int64(statement, position, Int64(number))
            }
        }
    }

    private func lastError() -> SearchIndexError {
        .sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")
    }
}

enum SearchIndexError: Error, Equatable {
    case sqlite(String)
}
