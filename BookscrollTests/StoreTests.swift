import SwiftData
import XCTest
@testable import Bookscroll

/// SwiftData queries, writing and deleting books.
final class StoreTests: XCTestCase {
    func testKeyQueriesMatchTheSegmentation() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let paragraphs = Fixtures.paragraphs(count: 240, chapterEvery: 25, seed: 3)
        let segmented = Segmenter.segment(paragraphs)
        let otherID = try Fixtures.writeBook(title: "Other", paragraphs: 50, seed: 9, into: context)
        let parsed = ParsedBook(title: "Main", author: "Tester", format: .pdf, paragraphs: paragraphs, passagesOnly: false, note: nil)
        let bookID = try BookWriter.write(parsed: parsed, segmented: segmented, into: context)
        let store = LibraryStore(context: context)
        let book = try XCTUnwrap(store.feedBook(id: bookID))
        XCTAssertNotEqual(book.ordinal, store.feedBook(id: otherID)?.ordinal)

        for style in PostStyle.allCases {
            let drafts = style == .paragraph ? segmented.paragraphs : segmented.passages
            let stored = store.segments(book: book, style: style, from: 0, limit: drafts.count + 10)
            XCTAssertEqual(stored, drafts.map { SegmentRecord(bookID: bookID, draft: $0) }, "\(style) round trip")
            for draft in drafts {
                for offset in [draft.charStart, draft.charEnd - 1] {
                    XCTAssertEqual(store.indexContaining(offset: offset, book: book, style: style), draft.index, "\(style) offset \(offset)")
                }
            }
            XCTAssertEqual(store.indexContaining(offset: -5, book: book, style: style), 0)
            XCTAssertEqual(store.indexContaining(offset: book.totalCharacters + 100, book: book, style: style), drafts.count - 1)
            XCTAssertEqual(store.segments(book: book, style: style, from: 10, limit: 3).map(\.index), [10, 11, 12])
            XCTAssertEqual(store.segments(book: book, style: style, before: 10, limit: 3).map(\.index), [7, 8, 9])
            XCTAssertEqual(store.segments(book: book, style: style, before: 2, limit: 5).map(\.index), [0, 1])
            XCTAssertTrue(store.segments(book: book, style: style, before: 0, limit: 5).isEmpty)
            XCTAssertTrue(store.segments(book: book, style: style, from: drafts.count, limit: 5).isEmpty)
            XCTAssertTrue(store.segments(book: book, style: style, from: 0, limit: 0).isEmpty)
            XCTAssertTrue(stored.allSatisfy { $0.bookID == bookID && $0.style == style })
        }

        // Overlap: a paragraph range maps onto the passages that cover it.
        let paragraph = segmented.paragraphs[100]
        let overlapping = store.segmentsOverlapping(start: paragraph.charStart, end: paragraph.charEnd, book: book, style: .passage)
        let expected = segmented.passages.filter { $0.charStart < paragraph.charEnd && paragraph.charStart < $0.charEnd }
        XCTAssertEqual(overlapping.map(\.index), expected.map(\.index))
        XCTAssertFalse(overlapping.isEmpty)
    }

    func testPositionIsClampedToTheText() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let id = try Fixtures.writeBook(title: "Clamp", paragraphs: 10, into: context)
        let store = LibraryStore(context: context)
        let total = try XCTUnwrap(store.book(id: id)).totalCharacters

        store.setPosition(bookID: id, offset: -20)
        XCTAssertEqual(store.book(id: id)?.positionOffset, 0)
        store.setPosition(bookID: id, offset: total + 500)
        XCTAssertEqual(store.book(id: id)?.positionOffset, total - 1)
        store.setPosition(bookID: id, offset: 42)
        XCTAssertEqual(store.book(id: id)?.positionOffset, 42)
        store.setPosition(bookID: UUID(), offset: 1)
    }

    func testDeleterRemovesOnlyThatBookInChunks() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let keep = try Fixtures.writeBook(title: "Keep", paragraphs: 40, seed: 2, into: context)
        let drop = try Fixtures.writeBook(title: "Drop", paragraphs: 120, seed: 4, into: context)
        let store = LibraryStore(context: context)
        store.addMark(kind: .like, bookID: keep, charStart: 0, charEnd: 5)
        store.addMark(kind: .bookmark, bookID: drop, charStart: 0, charEnd: 5)
        let keepCount = try Fixtures.segmentCount(bookID: keep, in: container)
        XCTAssertGreaterThan(try Fixtures.segmentCount(bookID: drop, in: container), 7)

        try BookDeleter.delete(bookID: drop, in: ModelContext(container), chunkSize: 7)

        let fresh = ModelContext(container)
        XCTAssertEqual(try Fixtures.segmentCount(bookID: drop, in: container), 0)
        XCTAssertEqual(try Fixtures.segmentCount(bookID: keep, in: container), keepCount)
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<Book>()).map(\.title), ["Keep"])
        XCTAssertEqual(try fresh.fetch(FetchDescriptor<Mark>()).map(\.bookID), [keep])

        // Deleting again (a resumed deletion that already finished) is harmless.
        XCTAssertNoThrow(try BookDeleter.delete(bookID: drop, in: fresh))
    }

    func testPendingDeletionHidesTheBookAndIsFoundAgain() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let id = try Fixtures.writeBook(title: "Pending", paragraphs: 20, into: context)
        let store = LibraryStore(context: context)
        XCTAssertEqual(store.feedBooks().map(\.id), [id])

        store.markForDeletion(id: id)
        XCTAssertTrue(store.feedBooks().isEmpty, "Hidden from Feed, Library and Saved at once")
        XCTAssertEqual(BookDeleter.pendingBookIDs(in: ModelContext(container)), [id], "Saved, so a relaunch finds it")

        // The same book can be imported again while the old copy is being deleted.
        XCTAssertNoThrow(try Fixtures.writeBook(title: "Pending", paragraphs: 20, into: ModelContext(container)))

        try BookDeleter.delete(bookID: id, in: ModelContext(container))
        XCTAssertTrue(BookDeleter.pendingBookIDs(in: ModelContext(container)).isEmpty)
        XCTAssertEqual(LibraryStore(context: ModelContext(container)).feedBooks().map(\.title), ["Pending"])
    }

    func testDuplicateBooksAreRejected() throws {
        let container = try Fixtures.makeContainer()
        try Fixtures.writeBook(title: "Twice", paragraphs: 15, into: ModelContext(container))
        XCTAssertThrowsError(try Fixtures.writeBook(title: "Twice", paragraphs: 15, into: ModelContext(container))) { error in
            XCTAssertEqual(error as? BookImportError, .duplicate("Twice"))
            XCTAssertEqual((error as? LocalizedError)?.errorDescription, "\u{201C}Twice\u{201D} is already in your library.")
        }
        // Same title, different text: a different book.
        XCTAssertNoThrow(try Fixtures.writeBook(title: "Twice", paragraphs: 16, into: ModelContext(container)))
        XCTAssertNoThrow(try Fixtures.writeBook(title: "Twice", author: "Someone Else", paragraphs: 15, into: ModelContext(container)))
    }

    func testOrdinalsAreNeverReusedWhileSegmentsRemain() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        XCTAssertEqual(try BookWriter.nextOrdinal(in: context), 1)
        let first = try Fixtures.writeBook(title: "First", paragraphs: 5, into: context)
        XCTAssertEqual(try BookWriter.nextOrdinal(in: context), 2)

        // A segment left behind with a higher ordinal (no book row) still blocks that ordinal.
        let stray = SegmentDraft(style: .paragraph, index: 0, charStart: 0, charEnd: 10, chapter: "", text: "Stray text")
        context.insert(Segment(bookID: UUID(), ordinal: 7, draft: stray))
        try context.save()
        XCTAssertEqual(try BookWriter.nextOrdinal(in: context), 8)

        try BookDeleter.delete(bookID: first, in: context)
        XCTAssertEqual(try BookWriter.nextOrdinal(in: context), 8)
    }

    func testWriteReportsProgressAndStoresMetadata() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let parsed = ParsedBook(
            title: "Meta",
            author: "Writer",
            format: .pdf,
            paragraphs: Fixtures.paragraphs(count: 600, seed: 5),
            passagesOnly: true,
            note: "Shown as passages."
        )
        let segmented = Segmenter.segment(parsed.paragraphs)
        var reported: [Double] = []
        let id = try BookWriter.write(parsed: parsed, segmented: segmented, into: context) { reported.append($0) }

        XCTAssertEqual(reported.last, 1)
        XCTAssertEqual(reported, reported.sorted(), "Progress never goes back")
        XCTAssertGreaterThan(reported.count, 2)
        let book = try XCTUnwrap(LibraryStore(context: ModelContext(container)).book(id: id))
        XCTAssertEqual(book.format, .pdf)
        XCTAssertTrue(book.passagesOnly)
        XCTAssertEqual(book.importNote, "Shown as passages.")
        XCTAssertEqual(book.paragraphSegmentCount, segmented.paragraphs.count)
        XCTAssertEqual(book.passageSegmentCount, segmented.passages.count)
        XCTAssertFalse(book.deletionPending)
        XCTAssertEqual(FeedBook(book).effectiveStyle(.paragraph), .passage)
        XCTAssertEqual(try Fixtures.segmentCount(bookID: id, in: container), segmented.paragraphs.count + segmented.passages.count)
    }
}
