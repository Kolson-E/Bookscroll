import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Bookscroll

/// Files picker, "Open in Bookscroll", staging and the import queue.
@MainActor
final class ImportTests: XCTestCase {
    // MARK: Info.plist

    func testInfoPlistDeclaresEPUBAndPDFDocumentTypes() throws {
        // Unit tests run inside the app, so the main bundle is the built app.
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        XCTAssertEqual(contentTypes, ["org.idpf.epub-container", "com.adobe.pdf"])
        for type in types {
            XCTAssertEqual(type["LSHandlerRank"] as? String, "Alternate", "Bookscroll must not take over EPUB or PDF from other apps")
        }
        XCTAssertEqual(info["LSSupportsOpeningDocumentsInPlace"] as? Bool, false)
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Bookscroll", "Generated keys are still merged")
        XCTAssertEqual(BookFormat.importableTypes.map(\.identifier), ["org.idpf.epub-container", "com.adobe.pdf"])
    }

    // MARK: Staging

    func testStagingCopiesTheFileAndCleanUpRemovesTheCopy() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("My Book.epub")
        try Data("content".utf8).write(to: source)

        let staged = try FileStaging.stage(source)
        XCTAssertNotEqual(staged, source)
        XCTAssertEqual(staged.lastPathComponent, "My Book.epub")
        XCTAssertTrue(staged.deletingLastPathComponent().lastPathComponent.hasPrefix(FileStaging.stagingPrefix))
        XCTAssertEqual(try Data(contentsOf: staged), Data("content".utf8))

        FileStaging.cleanUp(staged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "The original is never touched")
    }

    func testStagingAMissingFileGivesAClearError() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).epub")
        XCTAssertThrowsError(try FileStaging.stage(missing)) { error in
            guard case .unreadable = error as? BookImportError else {
                return XCTFail("Expected unreadable, got \(error)")
            }
            XCTAssertTrue((error as? LocalizedError)?.errorDescription?.hasPrefix("The file could not be read.") == true)
        }
    }

    func testInboxCopiesAreRecognisedAndOnlyTheyAreRemoved() throws {
        XCTAssertTrue(FileStaging.isInboxCopy(FileStaging.inboxDirectory.appendingPathComponent("book.epub")))
        XCTAssertFalse(FileStaging.isInboxCopy(URL.documentsDirectory.appendingPathComponent("InboxOther/book.epub")))
        XCTAssertFalse(FileStaging.isInboxCopy(URL(string: "https://example.com/book.epub")!))

        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let outside = folder.appendingPathComponent("keep.epub")
        try Data("x".utf8).write(to: outside)
        FileStaging.removeIfInboxCopy(outside)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testLeftoverStagingFoldersAreRemoved() throws {
        let manager = FileManager.default
        let leftover = manager.temporaryDirectory.appendingPathComponent(FileStaging.stagingPrefix + UUID().uuidString)
        try manager.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: leftover.appendingPathComponent("half.epub"))
        let unrelated = try Fixtures.temporaryDirectory()
        defer { try? manager.removeItem(at: unrelated) }

        FileStaging.removeLeftovers()
        XCTAssertFalse(manager.fileExists(atPath: leftover.path))
        XCTAssertTrue(manager.fileExists(atPath: unrelated.path))
    }

    // MARK: Import queue

    func testQueueImportsFilesAndReportsFailuresPerFile() async throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = folder.appendingPathComponent("harbour.epub")
        try EPUBFixture.write(to: good)
        let notABook = folder.appendingPathComponent("notes.txt")
        try Data("Just some notes.".utf8).write(to: notABook)
        let missing = folder.appendingPathComponent("gone.pdf")

        let container = try Fixtures.makeContainer()
        let manager = ImportManager(container: container)
        var importedCount = 0
        manager.onImported = { importedCount += 1 }
        let finished = expectation(description: "queue finished")
        manager.onQueueFinished = { finished.fulfill() }

        manager.enqueue([good, notABook, missing, good])
        XCTAssertEqual(manager.jobs.count, 4)
        XCTAssertTrue(manager.isBusy)
        await fulfillment(of: [finished], timeout: 60)

        XCTAssertEqual(importedCount, 1)
        let failures = manager.jobs.map { job -> String in
            guard case let .failed(message) = job.status else { return "not failed: \(job.status)" }
            return job.fileName + ": " + message
        }
        XCTAssertEqual(failures.count, 3)
        guard failures.count == 3 else { return }
        XCTAssertEqual(failures[0], "notes.txt: This is not an EPUB or PDF file.")
        XCTAssertTrue(failures[1].hasPrefix("gone.pdf: The file could not be read."), failures[1])
        XCTAssertEqual(failures[2], "harbour.epub: \u{201C}The Harbour Tales\u{201D} is already in your library.")
        XCTAssertFalse(manager.isBusy)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<Book>()), 1)

        let first = try XCTUnwrap(manager.jobs.first)
        manager.dismiss(first.id)
        XCTAssertEqual(manager.jobs.count, 2)
    }

    // MARK: App routing

    func testOpenInBookscrollImportsTheFileAndShowsTheLibrary() async throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("harbour.epub")
        try EPUBFixture.write(to: url)

        let app = AppModel(container: try Fixtures.makeContainer())
        app.feed.configure(style: .paragraph, mode: .mix)
        XCTAssertTrue(app.feed.books.isEmpty)
        app.selectedTab = .saved

        let finished = expectation(description: "imported")
        app.importer.onQueueFinished = { finished.fulfill() }
        app.handleOpenURL(url)
        XCTAssertEqual(app.selectedTab, .library, "Progress and errors show in the Library")
        XCTAssertEqual(app.importer.jobs.map(\.fileName), ["harbour.epub"])
        await fulfillment(of: [finished], timeout: 60)

        XCTAssertTrue(app.importer.jobs.isEmpty)
        XCTAssertEqual(app.feed.books.map(\.title), ["The Harbour Tales"])
        XCTAssertFalse(app.feed.posts.isEmpty, "The feed fills as soon as the first book arrives")
        XCTAssertEqual(app.libraryVersion, 1)
    }

    func testOpenURLIgnoresNonFileURLs() throws {
        let app = AppModel(container: try Fixtures.makeContainer())
        app.handleOpenURL(URL(string: "https://example.com/book.epub")!)
        XCTAssertEqual(app.selectedTab, .feed)
        XCTAssertTrue(app.importer.jobs.isEmpty)
    }

    func testImportButtonsShowTheFilesPicker() throws {
        let app = AppModel(container: try Fixtures.makeContainer())
        XCTAssertFalse(app.isImporterPresented)
        app.presentImporter()
        XCTAssertTrue(app.isImporterPresented)

        app.handleImporterResult(.success([]))
        XCTAssertTrue(app.importer.jobs.isEmpty, "Cancelling the picker queues nothing")
        XCTAssertNil(app.errorMessage)

        struct PickerError: LocalizedError { var errorDescription: String? { "Picker failed" } }
        app.handleImporterResult(.failure(PickerError()))
        XCTAssertEqual(app.errorMessage, "Files could not be opened: Picker failed")
    }
}
