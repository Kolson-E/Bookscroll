import SwiftData
import XCTest
@testable import Bookscroll

/// Settings › Storage: totals and per-book estimates.
final class StorageTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, bytes: Int) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    private func facts(_ id: UUID, _ title: String, characters: Int) -> StorageReport.BookFacts {
        StorageReport.BookFacts(id: id, title: title, author: "Ada Example", format: .epub, characters: characters)
    }

    func testTotalsAndSharesAddUp() throws {
        let database = try file("Library.store", bytes: 40_000)
        let wal = try file("Library.store-wal", bytes: 9_000)
        let shm = try file("Library.store-shm", bytes: 3_000)
        let search = try file("Search.sqlite", bytes: 20_000)
        let covers = folder.appendingPathComponent("Covers", isDirectory: true)
        let long = UUID()
        let short = UUID()
        let cover = try file("Covers/" + CoverStore.url(bookID: short, photo: false, in: covers).lastPathComponent, bytes: 30_000)

        let report = StorageReport.measure(
            books: [facts(short, "Short", characters: 1_000), facts(long, "Long", characters: 3_000)],
            at: .init(database: database, searchIndex: search, covers: covers)
        )
        let size = StorageReport.size(of:)
        XCTAssertEqual(report.database, size(database) + size(wal) + size(shm), "The write-ahead log counts")
        XCTAssertEqual(report.searchIndex, size(search))
        XCTAssertEqual(report.covers, size(cover))
        XCTAssertEqual(report.total, report.database + report.searchIndex + report.covers)
        XCTAssertGreaterThan(report.database, 52_000)

        let shared = report.database + report.searchIndex
        let byID = Dictionary(uniqueKeysWithValues: report.books.map { ($0.id, $0.bytes) })
        XCTAssertEqual(Double(byID[long] ?? 0), Double(shared) * 0.75, accuracy: 1)
        XCTAssertEqual(Double(byID[short] ?? 0), Double(shared) * 0.25 + Double(size(cover)), accuracy: 1)
        XCTAssertEqual(Double(report.books.reduce(0) { $0 + $1.bytes }), Double(report.total), accuracy: 2, "The shares add up to the total")
    }

    func testBooksAreListedLargestFirstWithTiesByTitle() {
        let a = UUID(), b = UUID(), c = UUID()
        let database = try? file("Library.store", bytes: 100_000)
        let report = StorageReport.measure(
            books: [facts(a, "Beta", characters: 10), facts(b, "Alpha", characters: 10), facts(c, "Gamma", characters: 50)],
            at: .init(database: database, searchIndex: nil, covers: folder.appendingPathComponent("Covers"))
        )
        XCTAssertEqual(report.books.map(\.title), ["Gamma", "Alpha", "Beta"])
    }

    func testMissingFilesAndEmptyBooksCountAsZero() {
        let missing = folder.appendingPathComponent("nothing-here")
        let report = StorageReport.measure(
            books: [facts(UUID(), "Empty", characters: 0)],
            at: .init(database: nil, searchIndex: missing, covers: missing)
        )
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.books.map(\.bytes), [0])
        XCTAssertEqual(StorageReport.size(of: missing), 0)
    }

    func testFolderSizeIncludesSubfolders() throws {
        let top = try file("Tree/a.bin", bytes: 5_000)
        let nested = try file("Tree/inner/b.bin", bytes: 7_000)
        let size = StorageReport.size(of:)
        XCTAssertEqual(size(folder.appendingPathComponent("Tree")), size(top) + size(nested))
    }

    @MainActor
    func testAppReportListsTheLibrary() async throws {
        let container = try Fixtures.makeContainer()
        let url = folder.appendingPathComponent("harbour.epub")
        try EPUBFixture.write(to: url)
        try BookImporter.importBook(at: url, into: container)
        let app = AppModel(container: container)
        XCTAssertNil(app.storageLocations.database, "An in-memory library has no file")
        let report = await app.storageReport()
        XCTAssertEqual(report.books.map(\.title), ["The Harbour Tales"])
        XCTAssertEqual(report.books.first?.format, .epub)
    }
}
