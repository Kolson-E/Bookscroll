import SwiftData
import XCTest
@testable import Bookscroll

final class SearchIndexTests: XCTestCase {
    private func record(_ book: UUID, _ index: Int, _ text: String, style: PostStyle = .paragraph) -> SegmentRecord {
        SegmentRecord(bookID: book, style: style, index: index, charStart: index * 100, charEnd: index * 100 + 99, chapter: "One", text: text)
    }

    private func marked(_ word: String) -> String {
        "\(SearchIndex.markStart)\(word)\(SearchIndex.markEnd)"
    }

    // MARK: Query text

    func testMatchExpressionKeepsWordsOnlyAndMakesTheLastAPrefix() {
        XCTAssertEqual(SearchIndex.matchExpression(for: "Stone bridge"), "stone bridge*")
        XCTAssertEqual(SearchIndex.matchExpression(for: "brid"), "brid*")
        XCTAssertEqual(SearchIndex.matchExpression(for: "  "), nil)
        XCTAssertEqual(SearchIndex.matchExpression(for: "\"*()-:^"), nil)
        XCTAssertEqual(SearchIndex.matchExpression(for: "AND or NOT"), "and or not*", "Operators become plain words")
        XCTAssertEqual(SearchIndex.matchExpression(for: "NEAR(a b)"), "near a b*")
        XCTAssertEqual(SearchIndex.matchExpression(for: "don't"), "don t*")
        XCTAssertEqual(SearchIndex.matchExpression(for: "Café"), "café*")
    }

    // MARK: Index

    func testTheSystemSQLiteHasFTS5() throws {
        let index = try SearchIndex.inMemory()
        XCTAssertTrue(index.usesFTS5, "iOS 17 ships SQLite with FTS5; ranked results depend on it")
    }

    func testAddSearchAndRemove() throws {
        let index = try SearchIndex.inMemory()
        let first = UUID()
        let second = UUID()
        try index.add(bookID: first, paragraphs: [
            record(first, 0, "The river ran fast under the old stone bridge."),
            record(first, 1, "Nobody could remember when it was built."),
            record(first, 2, "A passage copy that must not be indexed: bridge.", style: .passage),
        ])
        try index.add(bookID: second, paragraphs: [
            record(second, 0, "They met at the café by the bridge."),
        ])

        XCTAssertEqual(index.indexedBookIDs(), [first, second])
        XCTAssertEqual(index.entryCount(bookID: first), 2, "Only Paragraphs style is indexed")

        let hits = index.search("bridge")
        XCTAssertEqual(Set(hits.map(\.bookID)), [first, second])
        XCTAssertTrue(hits.allSatisfy { $0.snippet.contains(marked("bridge")) }, "\(hits)")

        XCTAssertEqual(index.search("BRID").count, 2, "Prefix of the last word, any case")
        XCTAssertEqual(index.search("stone brid").map(\.index), [0], "Every word must match")
        XCTAssertEqual(index.search("bridge", bookID: second).map(\.bookID), [second])
        XCTAssertEqual(index.search("remember").first, SearchIndex.Hit(bookID: first, index: 1, snippet: "Nobody could \(marked("remember")) when it was built."))
        XCTAssertTrue(index.search("elephant").isEmpty)
        XCTAssertTrue(index.search("bridge", limit: 1).count == 1)
        if index.usesFTS5 {
            XCTAssertEqual(index.search("cafe").map(\.bookID), [second], "Accents are ignored")
        }

        // Re-adding replaces the book's entries.
        try index.add(bookID: first, paragraphs: [record(first, 0, "Only one paragraph now.")])
        XCTAssertEqual(index.entryCount(bookID: first), 1)
        XCTAssertTrue(index.search("remember").isEmpty)

        try index.remove(bookID: first)
        XCTAssertEqual(index.indexedBookIDs(), [second])
        XCTAssertEqual(index.entryCount(bookID: first), 0)
        XCTAssertEqual(index.search("bridge").map(\.bookID), [second])
    }

    func testOddQueriesNeverFail() throws {
        let index = try SearchIndex.inMemory()
        let book = UUID()
        try index.add(bookID: book, paragraphs: [record(book, 0, "Near the end, and not before, or after.")])
        for query in ["\"", "NEAR(", "AND", "not", "*", "or after", "end\"", "a:b", "-near", "'; DROP TABLE paragraphs; --"] {
            _ = index.search(query)
        }
        XCTAssertEqual(index.search("and not").count, 1)
        XCTAssertEqual(index.entryCount(bookID: book), 1, "The table is intact")
    }

    func testFileIndexPersistsAndIsExcludedFromBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SearchIndex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Search.sqlite")
        let book = UUID()
        do {
            let index = try SearchIndex(url: url)
            try index.add(bookID: book, paragraphs: [record(book, 0, "Swallows left for warmer places.")])
        }
        let reopened = try SearchIndex(url: url)
        XCTAssertEqual(reopened.indexedBookIDs(), [book])
        XCTAssertEqual(reopened.search("swallow").count, 1)
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    // MARK: Library sync

    func testIndexMissingBooksReadsTheLibraryInBatchesAndDropsGoneBooks() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let first = try Fixtures.writeBook(title: "First", paragraphs: 45, seed: 1, into: context)
        let second = try Fixtures.writeBook(title: "Second", paragraphs: 14, seed: 2, into: context)
        let index = try SearchIndex.inMemory()

        try index.indexMissingBooks(container: container, batchSize: 7)
        XCTAssertEqual(index.indexedBookIDs(), [first, second])
        XCTAssertEqual(index.entryCount(bookID: first), 45)
        XCTAssertEqual(index.entryCount(bookID: second), 14, "A multiple of the batch size still finishes")
        XCTAssertFalse(index.search("swallows").isEmpty)

        // Indexed books are not read again.
        try index.remove(bookID: second)
        try index.add(bookID: first, paragraphs: [record(first, 0, "Changed.")])
        try index.indexMissingBooks(container: container, batchSize: 7)
        XCTAssertEqual(index.entryCount(bookID: first), 1)
        XCTAssertEqual(index.entryCount(bookID: second), 14)

        try BookDeleter.delete(bookID: second, in: context)
        try index.indexMissingBooks(container: container, batchSize: 7)
        XCTAssertEqual(index.indexedBookIDs(), [first])
        XCTAssertEqual(index.entryCount(bookID: second), 0)
    }

    @MainActor
    func testAppKeepsTheIndexInStepWithImportAndDelete() async throws {
        let container = try Fixtures.makeContainer()
        let kept = try Fixtures.writeBook(title: "Kept", paragraphs: 20, seed: 1, into: ModelContext(container))
        let index = try SearchIndex.inMemory()
        let app = AppModel(container: container, searchIndex: index)
        await app.syncSearchIndex()?.value
        XCTAssertEqual(index.indexedBookIDs(), [kept], "Existing books are indexed at launch")

        let added = try Fixtures.writeBook(title: "Added", paragraphs: 12, seed: 3, into: ModelContext(container))
        app.libraryDidChange()
        await app.syncSearchIndex()?.value
        XCTAssertEqual(index.indexedBookIDs(), [kept, added])
        XCTAssertEqual(index.entryCount(bookID: added), 12)

        await app.deleteBook(id: added)?.value
        await app.syncSearchIndex()?.value
        XCTAssertEqual(index.indexedBookIDs(), [kept])
        XCTAssertTrue(index.search("bridge").allSatisfy { $0.bookID == kept })
    }

    @MainActor
    func testAppWithoutAnIndexStillWorks() throws {
        let app = AppModel(container: try Fixtures.makeContainer())
        XCTAssertNil(app.syncSearchIndex())
    }
}
