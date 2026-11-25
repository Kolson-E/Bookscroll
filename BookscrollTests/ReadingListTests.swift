import SwiftData
import XCTest
@testable import Bookscroll

/// The reading list: sets of books read in order, the feed's Reading list mode, and books
/// that finish when the reader scrolls past their last post.
@MainActor
final class ReadingListTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "ReadingListTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private struct Library {
        let source: InMemorySegmentSource
        var books: [FeedBook]
    }

    private func makeLibrary(bookCount: Int, paragraphs: Int) -> Library {
        let source = InMemorySegmentSource()
        var books: [FeedBook] = []
        for i in 0..<bookCount {
            let id = UUID()
            let book = Segmenter.segment(Fixtures.paragraphs(count: paragraphs, chapterEvery: 100, seed: i + 11))
            source.add(bookID: id, segmented: book)
            books.append(Fixtures.feedBook(id: id, ordinal: i + 1, title: "Book \(i)", segmented: book))
        }
        return Library(source: source, books: books)
    }

    private func readingList(_ sets: [[UUID]]) -> FeedMode {
        .readingList(ReadingListSelection(sets: sets, names: sets.indices.map { "Set \($0 + 1)" }))
    }

    // MARK: Feed

    func testEachSetIsReadToItsEndBeforeTheNextSetStarts() {
        let library = makeLibrary(bookCount: 4, paragraphs: 10)
        let ids = library.books.map(\.id)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph,
                                mode: readingList([[ids[0], ids[1]], [ids[2]], [ids[3]]]), seed: 5)
        engine.loadMore(15)
        XCTAssertEqual(Set(engine.posts.map(\.bookID)), [ids[0], ids[1]], "The first set's books are mixed")
        engine.loadMore(100)
        let order = engine.posts.map(\.bookID)
        XCTAssertEqual(order.count, 40, "Every post of every set")
        XCTAssertEqual(Set(order.prefix(20)), [ids[0], ids[1]], "The first set ends before the second starts")
        XCTAssertEqual(Array(order[20..<30]), Array(repeating: ids[2], count: 10))
        XCTAssertEqual(Array(order[30..<40]), Array(repeating: ids[3], count: 10))
        XCTAssertTrue(engine.isAtEnd)
        XCTAssertTrue(engine.posts.allSatisfy(\.showsThreadButton), "Posts open in context, as in Mix")
    }

    func testFinishedBooksAndDoneSetsAreSkipped() {
        var library = makeLibrary(bookCount: 3, paragraphs: 8)
        library.books[0].finishedAt = Date()
        library.books[1].finishedAt = Date()
        let ids = library.books.map(\.id)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph,
                                mode: readingList([[ids[0], ids[1]], [ids[2]]]), seed: 1)
        engine.loadMore(5)
        XCTAssertEqual(Set(engine.posts.map(\.bookID)), [ids[2]], "A set whose books are finished is done")
    }

    func testAFinishedBookLeavesItsSetButTheOthersStay() {
        var library = makeLibrary(bookCount: 3, paragraphs: 8)
        library.books[1].finishedAt = Date()
        let ids = library.books.map(\.id)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph,
                                mode: readingList([[ids[0], ids[1]], [ids[2]]]), seed: 1)
        engine.loadMore(8)
        XCTAssertEqual(Set(engine.posts.map(\.bookID)), [ids[0]])
    }

    func testTheLastPostsOfASetStayWhenTheLibraryChanges() {
        let library = makeLibrary(bookCount: 2, paragraphs: 6)
        let ids = library.books.map(\.id)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph,
                                mode: readingList([[ids[0]], [ids[1]]]), seed: 1)
        engine.loadMore(12)
        XCTAssertEqual(engine.posts.count, 12)
        engine.updateBooks(library.books)
        XCTAssertEqual(engine.posts.count, 12, "Unseen posts of the first set stay while the second set loads")
    }

    func testScrollingPastTheLastPostReportsTheBookOnce() throws {
        let library = makeLibrary(bookCount: 1, paragraphs: 6)
        let id = library.books[0].id
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .single(id), seed: 1)
        engine.loadMore()
        XCTAssertEqual(engine.posts.count, 6)
        engine.markShown(through: engine.posts[4].id)
        XCTAssertEqual(engine.takeCompletedBooks(), [], "Not at the end yet")
        engine.markShown(through: engine.posts[5].id)
        XCTAssertEqual(engine.takeCompletedBooks(), [id])
        XCTAssertEqual(engine.takeCompletedBooks(), [], "Reported once")
    }

    func testModeChoiceResolvesTheReadingList() {
        let a = UUID(), b = UUID()
        let sets = [ReadingSet(name: "", bookIDs: [a]), ReadingSet(name: "Winter", bookIDs: [b])]
        let mode = FeedModeChoice.resolve(modeRaw: "readingList", singleBookID: "", feedShelfID: "", focusShelfID: "", shelves: [], readingSets: sets)
        XCTAssertEqual(mode, .readingList(ReadingListSelection(sets: [[a], [b]], names: ["Set 1", "Winter"])))
        XCTAssertEqual(
            FeedModeChoice.resolve(modeRaw: "readingList", singleBookID: "", feedShelfID: "", focusShelfID: "", shelves: [], readingSets: []),
            .mix,
            "An empty reading list falls back to Mix"
        )
    }

    // MARK: Store

    func testSetsKeepTheirOrderAndEachBookIsInOneSet() {
        let store = ReadingListStore(defaults: defaults)
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let first = try? XCTUnwrap(store.addSet(bookIDs: [a, b, a]))
        store.addSet(name: "Classics", bookIDs: [c])
        XCTAssertEqual(store.sets.map(\.bookIDs), [[a, b], [c]], "Repeats go")
        XCTAssertEqual(store.sets.map(store.displayName), ["Set 1", "Classics"])

        // A book chosen for a new set moves out of its old set; an empty set goes.
        store.addSet(bookIDs: [c, d])
        XCTAssertEqual(store.sets.map(\.bookIDs), [[a, b], [c, d]])
        XCTAssertEqual(store.sets.map(store.displayName), ["Set 1", "Set 2"])

        store.moveSet(store.sets[1].id, by: -1)
        XCTAssertEqual(store.sets.map(\.bookIDs), [[c, d], [a, b]])
        store.moveBooks(in: store.sets[0].id, fromOffsets: [1], toOffset: 0)
        XCTAssertEqual(store.sets[0].bookIDs, [d, c])

        if let first { store.rename(first, to: "  Now  ") }
        XCTAssertEqual(store.sets.map(store.displayName), ["Set 1", "Now"])

        // Kept between launches.
        let relaunched = ReadingListStore(defaults: defaults)
        XCTAssertEqual(relaunched.sets, store.sets)

        store.removeEverywhere(d)
        store.replaceEverywhere(c, with: b)
        XCTAssertEqual(store.sets.map(\.bookIDs), [[b], [a]], "Each book stays in one set")
        store.remove(a, from: store.sets[1].id)
        XCTAssertEqual(store.sets.count, 1, "A set with no books goes")
        XCTAssertNil(store.addSet(bookIDs: []))
    }

    func testStatusesShowWhatIsDoneNowAndNext() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), gone = UUID()
        let sets = [
            ReadingSet(bookIDs: [a, b]),
            ReadingSet(bookIDs: [gone]),
            ReadingSet(bookIDs: [c]),
            ReadingSet(bookIDs: [d]),
        ]
        let library: Set<UUID> = [a, b, c, d]
        XCTAssertEqual(ReadingListStore.statuses(of: sets, finished: [a], library: library), [.current, .empty, .upNext, .upNext])
        XCTAssertEqual(ReadingListStore.statuses(of: sets, finished: [a, b], library: library), [.done, .empty, .current, .upNext])
        XCTAssertEqual(ReadingListStore.statuses(of: sets, finished: [a, b, c, d], library: library), [.done, .empty, .done, .done])

        let store = ReadingListStore(defaults: defaults)
        store.addSet(bookIDs: [a, b])
        store.addSet(bookIDs: [c])
        store.removeDoneSets(finished: [a, b], library: library)
        XCTAssertEqual(store.sets.map(\.bookIDs), [[c]])
    }

    // MARK: App

    func testScrollingPastABooksEndFinishesItAndStartsTheNextSet() async throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let first = try Fixtures.writeBook(title: "Short", paragraphs: 4, seed: 1, into: context)
        let second = try Fixtures.writeBook(title: "Next", paragraphs: 4, seed: 2, into: context)
        let list = ReadingListStore(defaults: defaults)
        list.addSet(bookIDs: [first])
        list.addSet(bookIDs: [second])
        let app = AppModel(container: container, readingList: list)
        app.feed.configure(style: .paragraph, mode: .readingList(FeedModeChoice.readingList(list.sets)))

        let posts = app.feed.posts
        XCTAssertEqual(posts.map(\.bookID), Array(repeating: first, count: 4) + Array(repeating: second, count: 4))
        XCTAssertEqual(app.feed.title, "Set 1")
        app.feed.scrolledID = posts[4].id
        app.feed.didScroll(to: posts[4].id)
        XCTAssertNotNil(app.store.book(id: first)?.finishedAt, "Scrolling past the last post finishes the book")
        XCTAssertNil(app.store.book(id: second)?.finishedAt)
        XCTAssertEqual(app.feed.title, "Set 2", "The title follows the set at the top")
        XCTAssertEqual(app.feed.posts.count, 8, "The feed keeps its posts")

        // A relaunch starts at the second set.
        let relaunched = AppModel(container: container, readingList: ReadingListStore(defaults: defaults))
        relaunched.feed.configure(style: .paragraph, mode: .readingList(FeedModeChoice.readingList(list.sets)))
        XCTAssertEqual(relaunched.feed.posts.first?.bookID, second)

        // Deleting a book takes it out of the list.
        await relaunched.deleteBook(id: second)?.value
        XCTAssertNil(relaunched.readingList.set(containing: second))
    }

    func testBackupsKeepTheReadingList() throws {
        let old = #"{"version":1,"createdAt":"2026-01-01T00:00:00Z","books":[],"shelves":[]}"#
        let decoded = try LibraryBackup.decode(Data(old.utf8))
        XCTAssertNil(decoded.readingList, "Backups from before the reading list still open")

        let backup = LibraryBackup(createdAt: Date(timeIntervalSince1970: 0), books: [], shelves: [],
                                   readingList: [.init(name: "Set 1", books: [0, 1])])
        XCTAssertEqual(try LibraryBackup.decode(backup.encoded()).readingList, backup.readingList)
    }
}
