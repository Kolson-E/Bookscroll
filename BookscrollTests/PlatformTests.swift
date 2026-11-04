import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Bookscroll

/// Links, widgets, Spotlight, the Live Activity, the Focus filter, and drag and drop.
@MainActor
final class PlatformTests: XCTestCase {
    private func makeApp(books: [(String, Int)]) throws -> (AppModel, [UUID]) {
        let container = try Fixtures.makeContainer()
        var ids: [UUID] = []
        for (n, book) in books.enumerated() {
            ids.append(try Fixtures.writeBook(title: book.0, paragraphs: book.1, chapterEvery: 12, seed: n + 1, into: ModelContext(container)))
        }
        let app = AppModel(container: container)
        app.feed.configure(style: .paragraph, mode: .mix)
        return (app, ids)
    }

    // MARK: Links

    func testLinksRoundTrip() throws {
        let id = UUID()
        for link in [AppLink.continueReading, .book(id), .highlight(id)] {
            XCTAssertEqual(AppLink(url: link.url), link)
            if let spotlightID = link.spotlightID {
                XCTAssertEqual(AppLink(spotlightID: spotlightID), link)
            }
        }
        XCTAssertEqual(AppLink.book(id).url.absoluteString, "bookscroll://book/\(id.uuidString)")
        XCTAssertEqual(AppLink(url: try XCTUnwrap(URL(string: "BOOKSCROLL://Continue"))), .continueReading)
        XCTAssertNil(AppLink(url: try XCTUnwrap(URL(string: "bookscroll://book/not-an-id"))))
        XCTAssertNil(AppLink(url: try XCTUnwrap(URL(string: "bookscroll://shelf/\(id.uuidString)"))))
        XCTAssertNil(AppLink(url: try XCTUnwrap(URL(string: "https://book/\(id.uuidString)"))))
        XCTAssertNil(AppLink(url: URL(fileURLWithPath: "/tmp/book.epub")))
        XCTAssertNil(AppLink(spotlightID: "shelf:\(id.uuidString)"))
        XCTAssertNil(AppLink(spotlightID: "book"))
    }

    func testLinksOpenBooksHighlightsAndTheLastBook() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 40), ("Beta", 40)])
        let beta = try XCTUnwrap(app.store.feedBook(id: ids[1]))
        let place = try XCTUnwrap(app.store.segments(book: beta, style: .paragraph, from: 7, limit: 1).first)
        app.store.setPosition(bookID: ids[1], offset: place.charStart)

        app.selectedTab = .settings
        app.handleOpenURL(AppLink.continueReading.url)
        XCTAssertEqual(app.selectedTab, .feed)
        XCTAssertEqual(app.feed.mode, .single(ids[1]), "Continue opens the book read last")
        XCTAssertTrue(try XCTUnwrap(app.feed.posts.first).segment.contains(offset: place.charStart))

        app.open(.book(ids[0]))
        XCTAssertEqual(app.feed.mode, .single(ids[0]))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "singleBookID"), ids[0].uuidString)

        let mark = try XCTUnwrap(app.marks.addHighlight(bookID: ids[1], start: place.charStart, end: place.charStart + 20))
        app.openSpotlightItem(try XCTUnwrap(AppLink.highlight(mark.id).spotlightID))
        XCTAssertEqual(app.selectedTab, .saved)
        let reader = try XCTUnwrap(app.readerRequest)
        XCTAssertEqual(reader.model.book.id, ids[1])

        app.readerRequest = nil
        app.open(.highlight(UUID()))
        XCTAssertNil(app.readerRequest)
        XCTAssertEqual(app.errorMessage, "That highlight is no longer in your library.")
        app.open(.book(UUID()))
        XCTAssertEqual(app.errorMessage, "That book is no longer in your library.")
    }

    // MARK: Widgets

    func testWidgetShowsTheUnfinishedBookReadLast() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func book(_ name: String, position: Int, lastRead: TimeInterval?, finished: Bool = false) -> WidgetContent.BookFacts {
            WidgetContent.BookFacts(
                id: UUID(), title: name, author: "A", totalCharacters: 1_000, positionOffset: position,
                lastReadAt: lastRead.map { now.addingTimeInterval($0) }, finishedAt: finished ? now : nil
            )
        }
        let older = book("Older", position: 100, lastRead: -600)
        let newer = book("Newer", position: 250, lastRead: -60)
        let finished = book("Finished", position: 999, lastRead: -1, finished: true)
        let unread = book("Unread", position: 0, lastRead: nil)
        XCTAssertEqual(WidgetContent.currentBook([older, finished, newer, unread])?.title, "Newer")
        XCTAssertNil(WidgetContent.currentBook([finished, unread]))

        let snapshot = WidgetContent.snapshot(
            book: newer, upNext: String(repeating: "word ", count: 100), timeLeft: 25 * 60,
            secondsToday: 14.6 * 60, streak: 3, now: now
        )
        let current = try XCTUnwrap(snapshot.book)
        XCTAssertEqual(current.percent, 25)
        XCTAssertEqual(current.timeLeft, "about 25 min left")
        XCTAssertEqual(current.upNext.count, WidgetContent.upNextLength)
        XCTAssertEqual(snapshot.minutesToday, 15)
        XCTAssertEqual(snapshot.day, WidgetSnapshot.dayKey(now))

        let empty = WidgetContent.snapshot(book: nil, upNext: "", timeLeft: 0, secondsToday: 0, streak: 0, now: now)
        XCTAssertNil(empty.book)
    }

    func testWidgetDaysStreakAndFile() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let snapshot = WidgetSnapshot(book: nil, day: "2026-11-04", minutesToday: 30, streak: 5, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(snapshot.minutes(on: "2026-11-04"), 30)
        XCTAssertEqual(snapshot.minutes(on: "2026-11-05"), 0, "A new day starts at 0")
        XCTAssertEqual(snapshot.streak(on: "2026-11-04", calendar: calendar), 5)
        XCTAssertEqual(snapshot.streak(on: "2026-11-05", calendar: calendar), 5, "The streak holds the next day")
        XCTAssertEqual(snapshot.streak(on: "2026-11-06", calendar: calendar), 0)
        XCTAssertEqual(snapshot.streak(on: "2026-12-01", calendar: calendar), 0)

        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(WidgetSnapshot.fileName)
        XCTAssertTrue(SharedContainer.write(.placeholder, to: url))
        XCTAssertEqual(SharedContainer.readSnapshot(from: url), .placeholder)
        XCTAssertFalse(SharedContainer.write(.placeholder, to: nil))
        XCTAssertNil(SharedContainer.readSnapshot(from: folder.appendingPathComponent("missing.json")))
    }

    func testAppWidgetSnapshotFollowsReading() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 40)])
        XCTAssertNil(app.widgetSnapshot(books: app.store.allBooks()).book, "Nothing read yet")

        app.feed.configure(style: .paragraph, mode: .single(ids[0]))
        let posts = app.feed.posts
        app.feed.didScroll(to: posts[5].id)
        let snapshot = app.widgetSnapshot(books: app.store.allBooks())
        let book = try XCTUnwrap(snapshot.book)
        XCTAssertEqual(book.id, ids[0])
        XCTAssertEqual(book.title, "Alpha")
        XCTAssertEqual(book.upNext, String(posts[5].segment.text.prefix(WidgetContent.upNextLength)), "Up next is the paragraph at the place")
        XCTAssertEqual(book.percent, TextUtils.percent(posts[5].segment.charStart, of: posts[5].bookTotalCharacters))
    }

    // MARK: Spotlight

    func testSpotlightEntries() throws {
        let id = UUID()
        let entries = SpotlightContent.entries(
            books: [
                .init(id: id, title: "Harbour", author: "Ada", percent: 42, isFinished: false, thumbnail: nil),
                .init(id: UUID(), title: "Done", author: "Ben", percent: 100, isFinished: true, thumbnail: nil),
            ],
            highlights: [.init(id: UUID(), bookTitle: "Harbour", bookAuthor: "Ada", text: String(repeating: "x", count: 400))]
        )
        XCTAssertEqual(entries.map(\.title), ["Harbour", "Done", "Highlight in Harbour"])
        XCTAssertEqual(entries[0].detail, "Ada \u{00B7} 42% read")
        XCTAssertEqual(entries[1].detail, "Ben \u{00B7} Finished")
        XCTAssertEqual(entries[0].id, "book:\(id.uuidString)")
        XCTAssertEqual(entries[2].detail.count, SpotlightContent.highlightLength)
        XCTAssertTrue(entries[2].keywords.contains("Ada"))

        let item = SpotlightIndexer.item(entries[0])
        XCTAssertEqual(item.uniqueIdentifier, "book:\(id.uuidString)")
        XCTAssertEqual(item.domainIdentifier, SpotlightIndexer.domain)
        XCTAssertEqual(item.attributeSet.title, "Harbour")
    }

    func testAppSpotlightEntriesHoldBooksAndHighlights() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 20), ("Beta", 20)])
        let mark = try XCTUnwrap(app.marks.addHighlight(bookID: ids[0], start: 0, end: 10))
        let entries = app.spotlightEntries(books: app.store.allBooks())
        XCTAssertEqual(Set(entries.compactMap(\.link.spotlightID)), Set([
            AppLink.book(ids[0]).spotlightID, AppLink.book(ids[1]).spotlightID, AppLink.highlight(mark.id).spotlightID,
        ].compactMap { $0 }))
    }

    // MARK: Live Activity

    func testLiveActivityStartsUpdatesAndWaits() {
        let book = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = ReadingActivityAttributes.ContentState(percent: 10, minutesToday: 5, timeLeft: "about 2 h left", isPaused: false)
        func decide(current: UUID?, last: ReadingActivityAttributes.ContentState?, lastUpdate: TimeInterval, new: ReadingActivityAttributes.ContentState) -> ReadingActivityPlan {
            ReadingActivityPlan.decide(currentBook: current, lastState: last, lastUpdate: now.addingTimeInterval(lastUpdate), book: book, state: new, now: now)
        }
        XCTAssertEqual(decide(current: nil, last: nil, lastUpdate: 0, new: state), .start)
        XCTAssertEqual(decide(current: UUID(), last: state, lastUpdate: 0, new: state), .start, "Another book starts a new activity")
        XCTAssertEqual(decide(current: book, last: state, lastUpdate: -5, new: state), .none)
        var later = state
        later.minutesToday = 6
        XCTAssertEqual(decide(current: book, last: state, lastUpdate: -5, new: later), .none, "Waits 30 seconds between updates")
        XCTAssertEqual(decide(current: book, last: state, lastUpdate: -31, new: later), .update)
        later.percent = 11
        XCTAssertEqual(decide(current: book, last: state, lastUpdate: -5, new: later), .update, "A new percent shows at once")
    }

    // MARK: Focus filter

    func testFocusShelfComesBeforeTheReadersChoice() throws {
        let shelf = ShelfRecord(id: UUID(), name: "Calm", bookIDs: [UUID()], sortIndex: 0)
        let other = ShelfRecord(id: UUID(), name: "Work", bookIDs: [], sortIndex: 1)
        let book = UUID()
        func resolve(_ mode: String, focus: String) -> FeedMode {
            FeedModeChoice.resolve(modeRaw: mode, singleBookID: book.uuidString, feedShelfID: other.id.uuidString, focusShelfID: focus, shelves: [shelf, other])
        }
        let calm = FeedMode.shelf(ShelfSelection(id: shelf.id, name: "Calm", bookIDs: shelf.bookIDs))
        XCTAssertEqual(resolve("single", focus: shelf.id.uuidString), calm)
        XCTAssertEqual(resolve("mix", focus: shelf.id.uuidString), calm)
        XCTAssertEqual(resolve("single", focus: ""), .single(book))
        XCTAssertEqual(resolve("shelf", focus: ""), .shelf(ShelfSelection(id: other.id, name: "Work", bookIDs: [])))
        XCTAssertEqual(resolve("single", focus: UUID().uuidString), .single(book), "A deleted Focus shelf is ignored")
        XCTAssertEqual(resolve("mix", focus: ""), .mix)
        XCTAssertEqual(
            FeedModeChoice.resolve(modeRaw: "shelf", singleBookID: "", feedShelfID: UUID().uuidString, focusShelfID: "", shelves: [shelf]),
            .mix
        )

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FocusTest-\(UUID().uuidString)"))
        FocusFeed.set(shelfID: shelf.id, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: FocusFeed.key), shelf.id.uuidString)
        FocusFeed.set(shelfID: nil, defaults: defaults)
        XCTAssertNil(defaults.string(forKey: FocusFeed.key))
    }

    // MARK: Drag and drop

    func testDroppedFilesAreCopiedAndTextIsNotAFile() async throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Notes.md")
        try Data("# Title\n\nSome words.".utf8).write(to: file)

        let provider = try XCTUnwrap(NSItemProvider(contentsOf: file))
        provider.suggestedName = "Notes"
        let type = try XCTUnwrap(DroppedFiles.bookType(of: provider))
        XCTAssertTrue(UTType(type)?.conforms(to: BookFormat.markdownType) ?? false, type)

        let text = NSItemProvider(object: "A post with its citation" as NSString)
        XCTAssertNil(DroppedFiles.bookType(of: text), "Text dragged from a post is not imported")
        let image = NSItemProvider(item: Data([0x89, 0x50]) as NSData, typeIdentifier: UTType.png.identifier)
        image.suggestedName = "Photo"
        XCTAssertNil(DroppedFiles.bookType(of: image))

        let copy = try XCTUnwrap(DroppedFiles.keepCopy(of: file, suggestedName: "Notes"))
        XCTAssertEqual(copy.lastPathComponent, "Notes.md", "The extension is kept")
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: file))
        XCTAssertEqual(DroppedFiles.keepCopy(of: file, suggestedName: "Other.markdown")?.lastPathComponent, "Other.markdown")
        XCTAssertEqual(DroppedFiles.keepCopy(of: file, suggestedName: nil)?.lastPathComponent, "Notes.md")

        let copied = await DroppedFiles.copy(from: [provider, text])
        XCTAssertEqual(copied.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(copied.first)), try Data(contentsOf: file))
    }
}
