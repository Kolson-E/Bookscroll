import SwiftData
import XCTest
@testable import Bookscroll

/// Folder import and the synced folder.
@MainActor
final class FolderSyncTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
        suiteName = "FolderSyncTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @discardableResult
    private func file(_ path: String, _ text: String = "Some text.\n\nMore text.\n\nThe end.") throws -> URL {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map { FolderScan.relativePath(of: $0, in: folder) }
    }

    // MARK: Scan

    func testScanFindsBookFilesInSubfoldersAndSkipsTheRest() throws {
        try file("a.epub")
        try file("Novels/b.txt")
        try file("Novels/Deep/c.MD")
        try file("notes.docx")
        try file(".hidden.txt")
        try file(".git/config.txt")
        try file(".Remote Book.epub.icloud")
        XCTAssertEqual(names(FolderScan.bookFiles(in: folder)), ["a.epub", "Novels/b.txt", "Novels/Deep/c.MD"])
    }

    func testICloudPlaceholderNames() {
        XCTAssertEqual(FolderScan.iCloudPlaceholderTarget(".Book.epub.icloud"), "Book.epub")
        XCTAssertNil(FolderScan.iCloudPlaceholderTarget("Book.epub"))
        XCTAssertNil(FolderScan.iCloudPlaceholderTarget(".icloud"))
        XCTAssertNil(FolderScan.iCloudPlaceholderTarget("..icloud"))
    }

    // MARK: Sync

    func testSyncQueuesEachNewFileOnceAndRemembersTheFolder() throws {
        try file("one.txt")
        try file("Sub/two.txt")
        let sync = FolderSync(defaults: defaults)
        XCTAssertFalse(sync.isOn)
        var queued: [[String]] = []
        sync.enqueue = { urls, scope in
            XCTAssertEqual(scope.standardizedFileURL.resolvingSymlinksInPath(), self.folder.standardizedFileURL.resolvingSymlinksInPath())
            queued.append(self.names(urls))
        }

        sync.choose(folder)
        XCTAssertTrue(sync.isOn)
        XCTAssertEqual(sync.folderName, folder.lastPathComponent)
        XCTAssertEqual(queued, [["one.txt", "Sub/two.txt"]])
        XCTAssertEqual(sync.lastSyncCount, 2)
        XCTAssertNotNil(sync.lastSync)

        XCTAssertEqual(sync.sync(), 0, "Nothing new")
        try file("three.txt")
        XCTAssertEqual(sync.sync(), 1)
        XCTAssertEqual(queued.last, ["three.txt"])

        // A new FolderSync (the next launch) reads the folder and the files it has seen.
        let next = FolderSync(defaults: defaults)
        var nextQueued: [URL] = []
        next.enqueue = { urls, _ in nextQueued += urls }
        XCTAssertTrue(next.isOn)
        XCTAssertEqual(next.folderName, folder.lastPathComponent)
        XCTAssertEqual(next.sync(), 0)
        try file("four.txt")
        XCTAssertEqual(next.sync(), 1)
        XCTAssertEqual(names(nextQueued), ["four.txt"])

        next.stop()
        XCTAssertFalse(next.isOn)
        XCTAssertNil(next.folderName)
        XCTAssertEqual(next.sync(), 0)
        for key in FolderSync.Key.all {
            XCTAssertNil(defaults.object(forKey: key), key)
        }
    }

    func testAMissingFolderShowsAnError() throws {
        let gone = folder.appendingPathComponent("Gone", isDirectory: true)
        try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        let sync = FolderSync(defaults: defaults)
        sync.choose(gone)
        XCTAssertNil(sync.errorMessage)
        try FileManager.default.removeItem(at: gone)
        XCTAssertEqual(sync.sync(), 0)
        XCTAssertNotNil(sync.errorMessage)
    }

    // MARK: App

    func testSyncedBooksImportAndDuplicatesAreSkippedQuietly() async throws {
        try EPUBFixture.write(to: folder.appendingPathComponent("harbour.epub"))
        try EPUBFixture.write(to: folder.appendingPathComponent("harbour copy.epub"))
        try file("notes.txt")
        let container = try Fixtures.makeContainer()
        let app = AppModel(container: container, folderSync: FolderSync(defaults: defaults))
        app.selectedTab = .settings
        let finished = expectation(description: "queue finished")
        app.importer.onQueueFinished = { finished.fulfill() }

        app.folderSync.choose(folder)
        XCTAssertEqual(app.importer.jobs.count, 3)
        XCTAssertEqual(app.selectedTab, .settings, "A sync does not change the tab")
        await fulfillment(of: [finished], timeout: 60)

        XCTAssertTrue(app.importer.jobs.isEmpty, "The duplicate leaves no error")
        let titles = try ModelContext(container).fetch(FetchDescriptor<Book>()).map(\.title).sorted()
        XCTAssertEqual(titles, ["The Harbour Tales", "notes"])
    }

    func testImportingAFolderImportsTheBooksInIt() async throws {
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Shelf"), withIntermediateDirectories: true)
        try EPUBFixture.write(to: folder.appendingPathComponent("Shelf/harbour.epub"))
        try file("Shelf/Sub/notes.txt")
        let container = try Fixtures.makeContainer()
        let app = AppModel(container: container, folderSync: FolderSync(defaults: defaults))
        let finished = expectation(description: "queue finished")
        app.importer.onQueueFinished = { finished.fulfill() }

        app.importFiles([folder.appendingPathComponent("Shelf", isDirectory: true)])
        XCTAssertEqual(app.selectedTab, .library)
        XCTAssertEqual(app.importer.jobs.map(\.fileName), ["harbour.epub", "notes.txt"])
        await fulfillment(of: [finished], timeout: 60)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Book>()), 2)

        let empty = folder.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        app.importFiles([empty])
        XCTAssertEqual(app.errorMessage, "The folder \u{201C}Empty\u{201D} has no EPUB, PDF, text, Markdown, HTML or RTF files.")
    }
}
