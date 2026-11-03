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
        XCTAssertEqual(BookscrollMigrationPlan.schemas.count, 2)
        XCTAssertEqual(BookscrollMigrationPlan.stages.count, 1)
        let names = Set(LibraryContainer.schema.entities.map(\.name))
        XCTAssertEqual(names, ["Book", "Segment", "Mark"])
        let bookAttributes = Set(LibraryContainer.schema.entities.first { $0.name == "Book" }?.attributes.map(\.name) ?? [])
        XCTAssertTrue(bookAttributes.isSuperset(of: ["hiddenFromMix", "snoozedUntil", "feedWeight", "autoWordLimit", "chapterTable", "derivedVersion"]))
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

    private func assertOpensAsVersionTwo(url: URL, bookID: UUID) throws {
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
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Mark>()), 1)
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
        try assertOpensAsVersionTwo(url: url, bookID: bookID)
    }

    func testVersionOneStoreMigratesToVersionTwo() throws {
        let url = folder.appendingPathComponent("V1.store")
        let bookID = try writeVersionOneLibrary(at: url, versioned: true)
        try assertOpensAsVersionTwo(url: url, bookID: bookID)
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
