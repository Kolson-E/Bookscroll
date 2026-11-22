import SwiftData
import XCTest
@testable import Bookscroll

/// Text anchors, Replace File and backups.
@MainActor
final class ReadingStateTests: XCTestCase {
    private var folder: URL!

    /// "First paragraph here." 0–21, "The second paragraph…" from 23, "special phrase" 50–64.
    private let versionOne = "First paragraph here.\n\nThe second paragraph has a special phrase in it.\n\nThird paragraph is the end."
    /// A new paragraph in front moves everything by 26: the second paragraph starts at 49.
    private let versionTwo = "A new opening paragraph.\n\nFirst paragraph here.\n\nThe second paragraph has a special phrase in it.\n\nThird paragraph is the end."

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: Anchors

    func testAnchorsFindTheSameWordsInChangedText() {
        let one = versionOne as NSString
        let two = versionTwo as NSString
        let place = TextAnchoring.anchor(at: 23, in: one)
        XCTAssertEqual(place.text, "The second paragraph has a special phrase in it.")
        XCTAssertEqual(TextAnchoring.locate(place, in: one), 23, "Same text: same offset")
        XCTAssertEqual(TextAnchoring.locate(place, in: two), 49)
        XCTAssertEqual(TextAnchoring.locate(TextAnchoring.anchor(at: 50, in: one), in: two), 76)

        // Text that is gone: the same fraction of the book.
        let lost = TextAnchor(offset: 50, total: 100, text: "words that are nowhere in the new text at all")
        XCTAssertEqual(TextAnchoring.locate(lost, in: two), two.length / 2)
        XCTAssertEqual(TextAnchoring.locate(lost, in: ""), 0)

        // Several matches: the one nearest the same fraction.
        let repeated = (Array(repeating: "Same words again here.", count: 10).joined(separator: "\n\n")) as NSString
        let late = TextAnchor(offset: 200, total: repeated.length, text: "Same words again here.")
        let found = TextAnchoring.locate(late, in: ("X" + (repeated as String)) as NSString)
        XCTAssertEqual(found, 1 + 192, "The match at 192 is nearest to 200")
    }

    func testAnchorAtTheEndAndInsideEmoji() {
        let text = "Ends with \u{1F600}" as NSString
        let anchor = TextAnchoring.anchor(at: text.length - 1, in: text)
        XCTAssertEqual(anchor.text, "\u{1F600}", "A composed character is never cut")
        XCTAssertEqual(TextAnchoring.anchor(at: 999, in: text).offset, text.length)
    }

    // MARK: Replace File

    func testReplacingAFileKeepsPlaceMarksDetailsAndShelves() async throws {
        let container = try Fixtures.makeContainer()
        let oldID = try BookImporter.importBook(at: try write(versionOne, name: "Short.txt"), into: container)
        let app = AppModel(container: container)
        app.store.setPosition(bookID: oldID, offset: 23)
        app.store.addMark(kind: .highlight, bookID: oldID, charStart: 50, charEnd: 64)
        app.setFinished(true, bookID: oldID)
        app.editDetails(bookID: oldID, title: "My Short Book", author: "Ada Example")
        let shelfID = try XCTUnwrap(app.shelves.create(name: "Favourites", bookIDs: [oldID]))
        app.store.save()

        let finished = expectation(description: "replaced")
        app.importer.onQueueFinished = { finished.fulfill() }
        app.replaceFile(of: oldID, with: try write(versionTwo, name: "Short v2.txt"))
        XCTAssertEqual(app.selectedTab, .library)
        await fulfillment(of: [finished], timeout: 60)
        XCTAssertTrue(app.importer.jobs.isEmpty, "\(app.importer.jobs)")

        let books = app.store.allBooks()
        XCTAssertEqual(books.count, 1, "The old version is gone")
        let book = try XCTUnwrap(books.first)
        XCTAssertNotEqual(book.id, oldID)
        XCTAssertEqual(book.title, "My Short Book")
        XCTAssertEqual(book.author, "Ada Example")
        XCTAssertEqual(book.sourceFileName, "Short v2.txt")
        XCTAssertEqual(book.positionOffset, 49)
        XCTAssertNotNil(book.finishedAt)
        let marks = app.store.allMarks().filter { $0.bookID == book.id }
        XCTAssertEqual(marks.map { [$0.charStart, $0.charEnd] }, [[76, 90]])
        XCTAssertEqual(app.shelves.shelf(id: shelfID)?.bookIDs, [book.id])
    }

    func testAReplacementIsNotADuplicateOfTheBookItReplaces() throws {
        let container = try Fixtures.makeContainer()
        let url = try write(versionOne, name: "Short.txt")
        let oldID = try BookImporter.importBook(at: url, into: container)
        XCTAssertThrowsError(try BookImporter.importBook(at: url, into: container))
        XCTAssertNoThrow(try BookImporter.importBook(at: url, into: container, replacing: oldID))
    }

    // MARK: Backup

    func testBackupAndRestore() async throws {
        let container = try Fixtures.makeContainer()
        let id = try BookImporter.importBook(at: try write(versionOne, name: "Short.txt"), into: container)
        let app = AppModel(container: container)
        app.store.setPosition(bookID: id, offset: 23)
        app.store.addMark(kind: .like, bookID: id, charStart: 23, charEnd: 73)
        app.setFinished(true, bookID: id)
        app.setHiddenFromMix(true, bookID: id)
        app.shelves.create(name: "Favourites", bookIDs: [id])
        app.store.save()

        let data = try await app.makeBackup(now: Date(timeIntervalSince1970: 1_800_000_000))
        let backup = try LibraryBackup.decode(data)
        XCTAssertEqual(backup.version, 1)
        XCTAssertEqual(backup.books.map(\.title), ["Short"])
        XCTAssertEqual(backup.books.first?.marks.count, 1)
        XCTAssertEqual(backup.shelves, [LibraryBackup.ShelfBackup(name: "Favourites", books: [0])])

        // Lose the state, then restore it.
        app.store.setPosition(bookID: id, offset: 0)
        app.setFinished(false, bookID: id)
        app.setHiddenFromMix(false, bookID: id)
        app.store.deleteMarks(ids: app.store.allMarks().map(\.id))
        for shelf in app.shelves.shelves { app.shelves.delete(shelf.id) }

        var withMissing = backup
        var gone = backup.books[0]
        gone.title = "Gone Book"
        gone.totalCharacters = 5
        withMissing.books.append(gone)
        let summary = try await app.restore(withMissing)
        XCTAssertEqual(summary, RestoreSummary(restored: 1, missing: ["Gone Book"], shelves: 1))
        XCTAssertEqual(summary.message, "1 book restored. 1 shelf restored. Not in your library: \u{201C}Gone Book\u{201D}. Import them, then restore again.")

        let book = try XCTUnwrap(app.store.book(id: id))
        XCTAssertEqual(book.positionOffset, 23)
        XCTAssertNotNil(book.finishedAt)
        XCTAssertTrue(book.hiddenFromMix)
        XCTAssertEqual(app.store.allMarks().map { [$0.charStart, $0.charEnd] }, [[23, 73]])
        XCTAssertEqual(app.shelves.shelves.map(\.name), ["Favourites"])
        XCTAssertEqual(app.shelves.shelves.first?.bookIDs, [id])

        // A second restore adds no copies.
        _ = try await app.restore(backup)
        XCTAssertEqual(app.store.allMarks().count, 1)
        XCTAssertEqual(app.shelves.shelves.count, 1)
        XCTAssertEqual(app.shelves.shelves.first?.bookIDs, [id])
    }

    func testBackupMatchingRules() {
        func state(_ title: String, _ author: String, _ format: String, _ total: Int) -> BookState {
            BookState(
                title: title, author: author, format: format, totalCharacters: total,
                position: TextAnchor(offset: 0, total: total, text: ""), finishedAt: nil, lastReadAt: nil,
                addedAt: .now, hiddenFromMix: false, snoozedUntil: nil, feedWeight: 1, showsCover: true,
                photo: nil, marks: []
            )
        }
        let a = UUID(), b = UUID(), c = UUID()
        let library = [
            LibraryBackup.LibraryBook(id: a, title: "Harbour", author: "Ada", format: "epub", totalCharacters: 100),
            LibraryBackup.LibraryBook(id: b, title: "Harbour", author: "Ada", format: "epub", totalCharacters: 120),
            LibraryBackup.LibraryBook(id: c, title: "Original Name", author: "Ben", format: "pdf", totalCharacters: 500),
        ]
        let matches = LibraryBackup.match([
            state("Harbour", "Ada", "epub", 120),     // exact: b
            state("Harbour", "Ada", "epub", 999),     // title and author: a (b is taken)
            state("Renamed", "Someone", "pdf", 500),  // format and length: c
            state("Missing", "Nobody", "epub", 1),
        ], to: library)
        XCTAssertEqual(matches, [b, a, c, nil])
    }

    func testBackupFileErrors() {
        XCTAssertThrowsError(try LibraryBackup.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? BackupError, .notABackup)
        }
        let newer = Data(#"{"version": 99, "createdAt": "2026-01-01T00:00:00Z", "books": [], "shelves": []}"#.utf8)
        XCTAssertThrowsError(try LibraryBackup.decode(newer)) {
            XCTAssertEqual($0 as? BackupError, .newerVersion)
        }
        XCTAssertEqual(LibraryBackup.fileName(for: Date(timeIntervalSince1970: 1_800_000_000)), "Bookscroll Backup 2027-01-15.json")
        XCTAssertEqual(RestoreSummary(restored: 2, missing: [], shelves: 0).message, "2 books restored.")
    }
}
