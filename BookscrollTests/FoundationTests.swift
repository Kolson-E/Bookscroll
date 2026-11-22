import SwiftData
import XCTest
@testable import Bookscroll

/// Schema versioning, the privacy manifest and periodic saves.
final class FoundationTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("Foundation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Schema

    func testSchemaVersionsAndPlan() {
        XCTAssertEqual(BookscrollSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(BookscrollSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(BookscrollSchemaV3.versionIdentifier, Schema.Version(3, 0, 0))
        XCTAssertEqual(BookscrollSchemaV4.versionIdentifier, Schema.Version(4, 0, 0))
        XCTAssertEqual(BookscrollMigrationPlan.schemas.count, 4)
        XCTAssertEqual(BookscrollMigrationPlan.stages.count, 3)
        let names = Set(LibraryContainer.schema.entities.map(\.name))
        XCTAssertEqual(names, ["Book", "Segment", "Mark", "Shelf"])
        let bookAttributes = Set(LibraryContainer.schema.entities.first { $0.name == "Book" }?.attributes.map(\.name) ?? [])
        XCTAssertTrue(bookAttributes.isSuperset(of: ["hiddenFromMix", "snoozedUntil", "feedWeight", "autoWordLimit", "chapterTable", "derivedVersion"]))
        XCTAssertTrue(bookAttributes.isSuperset(of: ["finishedAt", "lastReadAt", "language", "sourceFileName", "sourceFileSize", "showsCover"]))
        let frozenV2 = Schema(versionedSchema: BookscrollSchemaV2.self)
        let v2Attributes = Set(frozenV2.entities.first { $0.name == "Book" }?.attributes.map(\.name) ?? [])
        XCTAssertFalse(v2Attributes.contains("finishedAt"), "Version 2 stays frozen")
        XCTAssertEqual(Set(frozenV2.entities.map(\.name)), ["Book", "Segment", "Mark"])
        let markAttributes = Set(LibraryContainer.schema.entities.first { $0.name == "Mark" }?.attributes.map(\.name) ?? [])
        XCTAssertTrue(markAttributes.contains("colorRaw"))
        let frozenV3 = Schema(versionedSchema: BookscrollSchemaV3.self)
        let v3MarkAttributes = Set(frozenV3.entities.first { $0.name == "Mark" }?.attributes.map(\.name) ?? [])
        XCTAssertFalse(v3MarkAttributes.contains("colorRaw"), "Version 3 stays frozen")
    }

    /// Writes a book the way version 1 of the app did, with the frozen V1 models.
    private func writeVersionOneLibrary(at url: URL, versioned: Bool) throws -> UUID {
        let container: ModelContainer
        if versioned {
            let schema = Schema(versionedSchema: BookscrollSchemaV1.self)
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        } else {
            // Version 1 shipped without a versioned schema.
            container = try ModelContainer(
                for: BookscrollSchemaV1.Book.self, BookscrollSchemaV1.Segment.self, BookscrollSchemaV1.Mark.self,
                configurations: ModelConfiguration(url: url)
            )
        }
        let context = ModelContext(container)
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 30, chapterEvery: 10))
        let book = BookscrollSchemaV1.Book(
            ordinal: 1,
            title: "Old Store",
            author: "Version One",
            format: .epub,
            totalCharacters: segmented.totalCharacters,
            positionOffset: 120,
            passagesOnly: false,
            paragraphSegmentCount: segmented.paragraphs.count,
            passageSegmentCount: segmented.passages.count,
            importNote: nil
        )
        context.insert(book)
        var segments: [BookscrollSchemaV1.Segment] = []
        for draft in segmented.paragraphs + segmented.passages {
            let segment = BookscrollSchemaV1.Segment(bookID: book.id, ordinal: 1, draft: draft)
            context.insert(segment)
            segments.append(segment)
        }
        book.segments = segments
        context.insert(BookscrollSchemaV1.Mark(bookID: book.id, kind: .like, charStart: 0, charEnd: 10))
        try context.save()
        return book.id
    }

    private func assertOpensAsCurrentVersion(url: URL, bookID: UUID) throws {
        let container = try LibraryContainer.make(url: url)
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.map(\.title), ["Old Store"])
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.id, bookID)
        XCTAssertEqual(book.positionOffset, 120, "The reading position survives")
        XCTAssertFalse(book.hiddenFromMix)
        XCTAssertNil(book.snoozedUntil)
        XCTAssertEqual(book.feedWeight, 1)
        XCTAssertEqual(book.derivedVersion, 0, "Derived values wait for the backfill")
        XCTAssertNil(book.finishedAt)
        XCTAssertNil(book.lastReadAt)
        XCTAssertNil(book.language)
        XCTAssertNil(book.sourceFileName)
        XCTAssertEqual(book.sourceFileSize, 0)
        XCTAssertTrue(book.showsCover)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Shelf>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Mark>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Mark>()).first?.color, .noHighlight, "Old marks get the default colour")
        XCTAssertEqual(try Fixtures.segmentCount(bookID: bookID, in: container), book.paragraphSegmentCount + book.passageSegmentCount)

        let results = try DerivedDataBackfill.compute(container: container)
        XCTAssertEqual(results.map(\.bookID), [bookID])
        XCTAssertEqual(DerivedData.decode(results.first?.chapterTable).map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])

        // And it stays writable.
        _ = try Fixtures.writeBook(title: "New Book", paragraphs: 5, seed: 2, into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Book>()), 2)
    }

    /// Libraries made before the migration plan existed must open with it.
    func testUnversionedVersionOneStoreOpensWithThePlan() throws {
        let url = folder.appendingPathComponent("Unversioned.store")
        let bookID = try writeVersionOneLibrary(at: url, versioned: false)
        try assertOpensAsCurrentVersion(url: url, bookID: bookID)
    }

    func testVersionOneStoreMigratesToTheCurrentVersion() throws {
        let url = folder.appendingPathComponent("V1.store")
        let bookID = try writeVersionOneLibrary(at: url, versioned: true)
        try assertOpensAsCurrentVersion(url: url, bookID: bookID)
    }

    /// Writes a book the way version 2 of the app did, with the frozen V2 models.
    private func writeVersionTwoLibrary(at url: URL) throws -> UUID {
        let schema = Schema(versionedSchema: BookscrollSchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 30, chapterEvery: 10))
        let book = BookscrollSchemaV2.Book(
            ordinal: 1,
            title: "Old Store",
            author: "Version Two",
            format: .epub,
            totalCharacters: segmented.totalCharacters,
            positionOffset: 120,
            passagesOnly: false,
            paragraphSegmentCount: segmented.paragraphs.count,
            passageSegmentCount: segmented.passages.count,
            importNote: nil
        )
        book.hiddenFromMix = true
        book.feedWeight = 2
        book.autoWordLimit = 77
        context.insert(book)
        var segments: [BookscrollSchemaV2.Segment] = []
        for draft in segmented.paragraphs + segmented.passages {
            let segment = BookscrollSchemaV2.Segment(bookID: book.id, ordinal: 1, draft: draft)
            context.insert(segment)
            segments.append(segment)
        }
        book.segments = segments
        context.insert(BookscrollSchemaV2.Mark(bookID: book.id, kind: .bookmark, charStart: 0, charEnd: 10))
        try context.save()
        return book.id
    }

    func testVersionTwoStoreMigratesToVersionThree() throws {
        let url = folder.appendingPathComponent("V2.store")
        let bookID = try writeVersionTwoLibrary(at: url)
        let container = try LibraryContainer.make(url: url)
        let context = ModelContext(container)
        let book = try XCTUnwrap(try context.fetch(FetchDescriptor<Book>()).first)
        XCTAssertEqual(book.id, bookID)
        XCTAssertEqual(book.author, "Version Two")
        XCTAssertEqual(book.positionOffset, 120, "The reading position survives")
        XCTAssertTrue(book.hiddenFromMix, "Version 2 values survive")
        XCTAssertEqual(book.feedWeight, 2)
        XCTAssertEqual(book.autoWordLimit, 77)
        XCTAssertNil(book.finishedAt)
        XCTAssertNil(book.lastReadAt)
        XCTAssertTrue(book.showsCover)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Mark>()).map(\.kind), [.bookmark])
        XCTAssertEqual(try Fixtures.segmentCount(bookID: bookID, in: container), book.paragraphSegmentCount + book.passageSegmentCount)

        // New version 3 values save and read back.
        book.finishedAt = Date(timeIntervalSince1970: 1_000)
        book.language = "en"
        context.insert(Shelf(name: "Favourites", sortIndex: 0, bookIDs: [bookID]))
        try context.save()
        let reopened = ModelContext(try LibraryContainer.make(url: url))
        XCTAssertEqual(try reopened.fetch(FetchDescriptor<Book>()).first?.finishedAt, Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(try reopened.fetch(FetchDescriptor<Shelf>()).first?.bookIDs, [bookID])
    }

    /// Writes a library the way version 3 of the app did, with the frozen V3 models.
    private func writeVersionThreeLibrary(at url: URL) throws -> UUID {
        let schema = Schema(versionedSchema: BookscrollSchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 30, chapterEvery: 10))
        let book = BookscrollSchemaV3.Book(
            ordinal: 1,
            title: "Old Store",
            author: "Version Three",
            format: .epub,
            totalCharacters: segmented.totalCharacters,
            positionOffset: 120,
            passagesOnly: false,
            paragraphSegmentCount: segmented.paragraphs.count,
            passageSegmentCount: segmented.passages.count,
            importNote: nil
        )
        book.finishedAt = Date(timeIntervalSince1970: 2_000)
        book.language = "en"
        context.insert(book)
        var segments: [BookscrollSchemaV3.Segment] = []
        for draft in segmented.paragraphs + segmented.passages {
            let segment = BookscrollSchemaV3.Segment(bookID: book.id, ordinal: 1, draft: draft)
            context.insert(segment)
            segments.append(segment)
        }
        book.segments = segments
        context.insert(BookscrollSchemaV3.Mark(bookID: book.id, kind: .bookmark, charStart: 0, charEnd: 10))
        context.insert(BookscrollSchemaV3.Mark(bookID: book.id, kind: .like, charStart: 500, charEnd: 600))
        context.insert(BookscrollSchemaV3.Shelf(name: "Favourites", sortIndex: 0, bookIDs: [book.id]))
        try context.save()
        return book.id
    }

    @MainActor
    func testVersionThreeStoreMigratesToVersionFourAndLikesBecomeBookmarks() throws {
        let url = folder.appendingPathComponent("V3.store")
        let bookID = try writeVersionThreeLibrary(at: url)
        let container = try LibraryContainer.make(url: url)
        let context = ModelContext(container)
        let book = try XCTUnwrap(try context.fetch(FetchDescriptor<Book>()).first)
        XCTAssertEqual(book.id, bookID)
        XCTAssertEqual(book.positionOffset, 120, "The reading position survives")
        XCTAssertEqual(book.finishedAt, Date(timeIntervalSince1970: 2_000), "Version 3 values survive")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Shelf>()).first?.bookIDs, [bookID])
        let marks = try context.fetch(FetchDescriptor<Mark>())
        XCTAssertEqual(marks.count, 2)
        XCTAssertTrue(marks.allSatisfy { $0.color == .noHighlight }, "Old bookmarks have no highlight")

        // The app turns the like into a bookmark without a highlight.
        let app = AppModel(container: container)
        let kinds = app.store.allMarks().map(\.kind)
        XCTAssertEqual(kinds, [.bookmark, .bookmark])
        XCTAssertEqual(app.bookmarkCounts(), [.noHighlight: 2])

        // A colour saves and reads back.
        let mark = try XCTUnwrap(app.store.allMarks().first)
        app.store.setMarkColor(ids: [mark.id], color: .red)
        let reopened = ModelContext(try LibraryContainer.make(url: url))
        XCTAssertEqual(try reopened.fetch(FetchDescriptor<Mark>()).first { $0.id == mark.id }?.color, .red)
    }

    // MARK: Privacy manifest

    func testPrivacyManifestShipsInTheAppAndDeclaresNoTracking() throws {
        let bundle = Bundle(for: AppModel.self)
        let url = try XCTUnwrap(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"), "PrivacyInfo.xcprivacy is in the app bundle")
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        XCTAssertEqual(plist["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty, true)
        XCTAssertEqual((plist["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty, true)
        let apis = try XCTUnwrap(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let reasons = Dictionary(uniqueKeysWithValues: apis.compactMap { entry -> (String, [String])? in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] else { return nil }
            return (type, reasons)
        })
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryUserDefaults"], ["CA92.1"])
        XCTAssertEqual(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"], ["C617.1"])
    }

    // MARK: Saves while scrolling

    @MainActor
    func testSaveIfDueSavesAtMostEveryInterval() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let id = try Fixtures.writeBook(title: "Saves", paragraphs: 40, into: context)
        let store = LibraryStore(context: context)
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

        store.setPosition(bookID: id, offset: 100)
        store.saveIfDue(interval: 5, now: start)
        XCTAssertFalse(context.hasChanges, "The first change saves at once")

        store.setPosition(bookID: id, offset: 200)
        store.saveIfDue(interval: 5, now: start.addingTimeInterval(2))
        XCTAssertTrue(context.hasChanges, "Not again within the interval")

        store.saveIfDue(interval: 5, now: start.addingTimeInterval(5))
        XCTAssertFalse(context.hasChanges)
        let saved = try ModelContext(container).fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first
        XCTAssertEqual(saved?.positionOffset, 200, "Another context sees the saved position")
    }
}
