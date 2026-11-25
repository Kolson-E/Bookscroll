import XCTest
@testable import Bookscroll

/// Find Books (book files in allowed folders) and the feed's chosen books.
final class FindAndChooseTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FindTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "FindTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func write(_ path: String, _ text: String = "x") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: Find Books

    func testFindsBookFilesInFoldersAndSubfoldersOnce() throws {
        _ = try write("Downloads/Meditations.epub")
        _ = try write("Downloads/Novels/Middlemarch.pdf")
        _ = try write("Downloads/Novels/notes.docx")
        _ = try write("Downloads/.hidden/Secret.epub")
        _ = try write("Downloads/Novels/.Emma.epub.icloud")
        _ = try write("Other/Walden.txt")
        let downloads = root.appendingPathComponent("Downloads")
        let novels = downloads.appendingPathComponent("Novels")
        let other = root.appendingPathComponent("Other")

        let found = BookFinder.findFiles(
            in: [(downloads, "Downloads"), (novels, "Novels"), (other, "Other")],
            libraryFileNames: ["middlemarch.pdf"]
        )
        XCTAssertEqual(found.map(\.relativePath), ["Meditations.epub", "Novels/Emma.epub", "Novels/Middlemarch.pdf", "Walden.txt"])
        XCTAssertEqual(found.map(\.folderName), ["Downloads", "Downloads", "Downloads", "Other"], "A folder inside another lists its files once")
        XCTAssertEqual(found.map(\.format), [.epub, .epub, .pdf, .text])
        XCTAssertEqual(found.map(\.isInLibrary), [false, false, true, false], "Matched by file name, ignoring case")
        let emma = try XCTUnwrap(found.first { $0.title == "Emma" })
        XCTAssertFalse(emma.isDownloaded, "A file still in iCloud is listed, to download on import")
        XCTAssertNil(emma.size)
        XCTAssertEqual(found.first?.size, 1)
        XCTAssertEqual(found[2].subfolder, "Novels")
        XCTAssertEqual(found[0].subfolder, "")
    }

    @MainActor
    func testAllowedFoldersAreRememberedAndScanned() async throws {
        _ = try write("Books/Walden.epub")
        _ = try write("Books/Deep/Emma.pdf")
        let books = root.appendingPathComponent("Books")
        let finder = BookFinder(defaults: defaults)
        XCTAssertTrue(finder.folders.isEmpty)
        XCTAssertTrue(finder.add(books))
        XCTAssertTrue(finder.add(books), "Allowing a folder twice keeps one")
        XCTAssertEqual(finder.folders.map(\.name), ["Books"])

        let reloaded = BookFinder(defaults: defaults)
        XCTAssertEqual(reloaded.folders.map(\.name), ["Books"])
        await reloaded.scan(libraryFileNames: [])
        XCTAssertTrue(reloaded.hasScanned)
        XCTAssertNil(reloaded.errorMessage)
        XCTAssertEqual(reloaded.files.map(\.title), ["Emma", "Walden"])

        reloaded.remove(reloaded.folders[0].id)
        XCTAssertTrue(reloaded.files.isEmpty)
        XCTAssertTrue(BookFinder(defaults: defaults).folders.isEmpty)
    }

    func testFolderSyncStillSkipsFilesInICloud() throws {
        _ = try write("Sync/.Emma.epub.icloud")
        _ = try write("Sync/Walden.epub")
        XCTAssertEqual(FolderScan.bookFiles(in: root.appendingPathComponent("Sync")).map(\.lastPathComponent), ["Walden.epub"])
    }

    // MARK: Chosen books

    func testChosenBooksMixOrReadOne() {
        let a = UUID(), b = UUID()
        func resolve(_ stored: String, mode: String = "books") -> FeedMode {
            FeedModeChoice.resolve(modeRaw: mode, singleBookID: "", feedShelfID: "", focusShelfID: "", shelves: [], chosenBookIDs: stored)
        }
        XCTAssertEqual(resolve(FeedModeChoice.storage([a, b])), .shelf(FeedModeChoice.chosenBooks([a, b])))
        XCTAssertEqual(resolve(FeedModeChoice.storage([a])), .single(a), "One chosen book reads straight through")
        XCTAssertEqual(resolve(""), .mix)
        XCTAssertEqual(resolve(FeedModeChoice.storage([a, b]), mode: "mix"), .mix)
        XCTAssertEqual(FeedModeChoice.chosenBooks([a, b]).name, String(localized: "\(2) books"))
        XCTAssertEqual(FeedModeChoice.chosenBooks([a, b]).id, FeedModeChoice.chosenBooksID)

        let focus = ShelfRecord(id: UUID(), name: "Calm", bookIDs: [a], sortIndex: 0)
        XCTAssertEqual(
            FeedModeChoice.resolve(modeRaw: "books", singleBookID: "", feedShelfID: "", focusShelfID: focus.id.uuidString, shelves: [focus], chosenBookIDs: FeedModeChoice.storage([a, b])),
            .shelf(ShelfSelection(id: focus.id, name: "Calm", bookIDs: [a])),
            "A Focus shelf still comes first"
        )
    }

    func testChosenBookStorageDropsRepeatsAndBadIDs() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(FeedModeChoice.bookIDs(from: "\(a.uuidString),nonsense,\(b.uuidString),\(a.uuidString)"), [a, b])
        XCTAssertEqual(FeedModeChoice.bookIDs(from: FeedModeChoice.storage([b, a])), [b, a])
        XCTAssertEqual(FeedModeChoice.bookIDs(from: ""), [])
    }
}
