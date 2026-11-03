import SQLite3
import SwiftData
import XCTest
@testable import Bookscroll

/// Checks the "50 books, about 100,000 segments per style" requirement on an on-disk store.
final class ScaleTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeDiskContainer() throws -> (ModelContainer, URL) {
        let url = folder.appendingPathComponent("Library.store")
        let container = try ModelContainer(
            for: Book.self, Segment.self, Mark.self,
            configurations: ModelConfiguration(url: url)
        )
        return (container, url)
    }

    /// The segment lookups must be index range scans, not table scans. This reads SQLite's
    /// own query plan for the queries the store runs.
    func testSegmentKeyQueriesUseAnIndex() throws {
        let (container, url) = try makeDiskContainer()
        try Fixtures.writeBook(title: "Indexed", paragraphs: 50, into: ModelContext(container))

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(db) }

        let columns = rows(db, "PRAGMA table_info(ZSEGMENT)").compactMap { $0.count > 1 ? $0[1] : nil }
        XCTAssertTrue(columns.contains("ZINDEXKEY") && columns.contains("ZOFFSETKEY"), "Columns: \(columns)")
        let indexes = rows(db, "SELECT name, IFNULL(sql, '') FROM sqlite_master WHERE type = 'index' AND tbl_name = 'ZSEGMENT'")
        print("SCALE: ZSEGMENT indexes \(indexes)")

        let lower = SegmentKey.lowerBound(ordinal: 1, style: .paragraph)
        let upper = SegmentKey.upperBound(ordinal: 1, style: .paragraph)
        let queries = [
            "SELECT Z_PK FROM ZSEGMENT WHERE ZINDEXKEY >= \(lower) AND ZINDEXKEY < \(upper) ORDER BY ZINDEXKEY LIMIT 20",
            "SELECT Z_PK FROM ZSEGMENT WHERE ZINDEXKEY >= \(lower) AND ZINDEXKEY < \(lower + 10) ORDER BY ZINDEXKEY DESC LIMIT 25",
            "SELECT Z_PK FROM ZSEGMENT WHERE ZOFFSETKEY >= \(lower) AND ZOFFSETKEY <= \(lower + 500) ORDER BY ZOFFSETKEY DESC LIMIT 1",
        ]
        for sql in queries {
            let plan = rows(db, "EXPLAIN QUERY PLAN " + sql).map { $0.last ?? "" }
            print("SCALE: plan \(plan) for \(sql)")
            XCTAssertTrue(plan.contains { $0.contains("USING INDEX") || $0.contains("USING COVERING INDEX") }, "Not indexed: \(plan)")
            XCTAssertFalse(plan.contains { $0.contains("TEMP B-TREE") }, "Sorts in memory: \(plan)")
        }
    }

    /// 50 books with 2,000 paragraphs each: 100,000 paragraph segments plus their passages.
    func testFiftyBooksStayFast() throws {
        let (container, _) = try makeDiskContainer()
        let paragraphs = Fixtures.paragraphs(count: 2000, chapterEvery: 40, seed: 11)
        let segmented = Segmenter.segment(paragraphs)

        let writeStart = Date()
        for n in 0..<50 {
            let parsed = ParsedBook(title: "Book \(n)", author: "Author \(n % 7)", format: .epub, paragraphs: paragraphs, passagesOnly: false, note: nil)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            _ = try BookWriter.write(parsed: parsed, segmented: segmented, into: context)
        }
        let writeSeconds = Date().timeIntervalSince(writeStart)
        let context = ModelContext(container)
        let totalSegments = try context.fetchCount(FetchDescriptor<Segment>())
        XCTAssertEqual(totalSegments, 50 * (segmented.paragraphs.count + segmented.passages.count))
        print("SCALE: wrote 50 books, \(50 * segmented.paragraphs.count) paragraph and \(50 * segmented.passages.count) passage segments in \(format(writeSeconds)) s (\(format(writeSeconds / 50)) s per book)")

        let store = LibraryStore(context: context)
        let books = store.feedBooks()
        XCTAssertEqual(books.count, 50)

        // Random lookups as the feed and the reader make them.
        var rng = SeededGenerator(seed: 7)
        let lookups = 1000
        let lookupStart = Date()
        for _ in 0..<lookups {
            let book = books.randomElement(using: &rng)!
            let style: PostStyle = Bool.random(using: &rng) ? .paragraph : .passage
            let offset = Int.random(in: 0..<book.totalCharacters, using: &rng)
            let index = try XCTUnwrap(store.indexContaining(offset: offset, book: book, style: style))
            let batch = store.segments(book: book, style: style, from: index, limit: FeedEngine.fetchBatchSize)
            XCTAssertTrue(batch.first?.contains(offset: offset) == true)
        }
        let lookupMilliseconds = Date().timeIntervalSince(lookupStart) * 1000 / Double(lookups)
        print("SCALE: offset lookup plus 20-segment fetch: \(format(lookupMilliseconds)) ms on average")
        XCTAssertLessThan(lookupMilliseconds, 10, "A table scan of this store takes far longer")

        // The feed in Mix mode, page by page.
        let engine = FeedEngine(source: store, books: books, style: .paragraph, mode: .mix, seed: 3)
        var pageMilliseconds: [Double] = []
        for _ in 0..<20 {
            let start = Date()
            engine.loadMore()
            pageMilliseconds.append(Date().timeIntervalSince(start) * 1000)
        }
        XCTAssertEqual(engine.posts.count, 20 * FeedEngine.pageSize)
        XCTAssertEqual(Set(engine.posts.map(\.id)).count, engine.posts.count)
        let worst = pageMilliseconds.max() ?? 0
        let average = pageMilliseconds.reduce(0, +) / Double(pageMilliseconds.count)
        print("SCALE: feed page of \(FeedEngine.pageSize) posts: first \(format(pageMilliseconds[0])) ms, average \(format(average)) ms, worst \(format(worst)) ms")
        XCTAssertLessThan(worst, 500)

        // Deleting one large book.
        let deleteStart = Date()
        try BookDeleter.delete(bookID: books[0].id, in: ModelContext(container))
        print("SCALE: deleted one book of \(segmented.paragraphs.count + segmented.passages.count) segments in \(format(Date().timeIntervalSince(deleteStart))) s")
        XCTAssertEqual(try Fixtures.segmentCount(bookID: books[0].id, in: container), 0)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func rows(_ db: OpaquePointer?, _ sql: String) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return [["SQL error: " + String(cString: sqlite3_errmsg(db))]]
        }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String] = []
            for column in 0..<sqlite3_column_count(statement) {
                if let text = sqlite3_column_text(statement, column) {
                    row.append(String(cString: text))
                } else {
                    row.append("")
                }
            }
            result.append(row)
        }
        return result
    }
}
