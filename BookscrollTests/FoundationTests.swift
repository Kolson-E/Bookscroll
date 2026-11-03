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

    func testSchemaVersionOneHoldsEveryModel() {
        XCTAssertEqual(BookscrollSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        let names = Set(LibraryContainer.schema.entities.map(\.name))
        XCTAssertEqual(names, ["Book", "Segment", "Mark"])
        XCTAssertEqual(BookscrollMigrationPlan.schemas.count, 1)
    }

    /// Libraries made before the versioned schema must open with the migration plan.
    func testStoreFromBeforeTheMigrationPlanOpensWithIt() throws {
        let url = folder.appendingPathComponent("Library.store")
        let bookID: UUID
        do {
            let old = try ModelContainer(
                for: Book.self, Segment.self, Mark.self,
                configurations: ModelConfiguration(url: url)
            )
            let context = ModelContext(old)
            bookID = try Fixtures.writeBook(title: "Old Store", paragraphs: 30, into: context)
            context.insert(Mark(bookID: bookID, kind: .like, charStart: 0, charEnd: 10))
            try context.save()
        }

        let container = try LibraryContainer.make(url: url)
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(books.map(\.title), ["Old Store"])
        XCTAssertEqual(books.first?.id, bookID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Mark>()), 1)
        XCTAssertEqual(try Fixtures.segmentCount(bookID: bookID, in: container), books.first.map { $0.paragraphSegmentCount + $0.passageSegmentCount })

        // And it stays writable.
        _ = try Fixtures.writeBook(title: "New Book", paragraphs: 5, seed: 2, into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Book>()), 2)
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
