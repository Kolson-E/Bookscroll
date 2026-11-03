import SwiftData
import XCTest
@testable import Bookscroll

/// Read in context, marks, Saved, delete and "Continue in feed" through the app model.
@MainActor
final class AppFlowTests: XCTestCase {
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

    // MARK: Read in context

    func testReaderLoadsAWindowAroundThePostAndPagesBothWays() throws {
        let (app, ids) = try makeApp(books: [("Long", 300)])
        let book = try XCTUnwrap(app.store.feedBook(id: ids[0]))
        let target = try XCTUnwrap(app.store.segments(book: book, style: .paragraph, from: 100, limit: 1).first)
        let model = ContextReaderModel(store: app.store, book: book, charStart: target.charStart, charEnd: target.charEnd)

        XCTAssertEqual(model.anchorIndex, 100)
        XCTAssertEqual(model.paragraphs.first?.index, 100 - ContextReaderModel.window)
        XCTAssertEqual(model.paragraphs.last?.index, 100 + ContextReaderModel.window)
        XCTAssertEqual(model.paragraphs.map(\.index), Array(75...125))
        XCTAssertEqual(model.paragraphs.filter(model.isHighlighted).map(\.index), [100])
        XCTAssertEqual(model.continueOffset, target.charStart, "Before scrolling, continue from the post")

        var guardCount = 0
        while model.canLoadEarlier && guardCount < 100 { model.loadEarlier(); guardCount += 1 }
        while model.canLoadLater && guardCount < 200 { model.loadLater(); guardCount += 1 }
        XCTAssertEqual(model.paragraphs.map(\.index), Array(0..<300), "Contiguous, no gaps or repeats")

        model.topVisibleIndex = 90
        XCTAssertEqual(model.continueOffset, model.paragraphs[90].charStart)

        // Chapter headings appear at the top and where the chapter changes.
        XCTAssertEqual(model.chapterHeading(before: 0), "Chapter 1")
        XCTAssertNil(model.chapterHeading(before: 1))
        XCTAssertEqual(model.chapterHeading(before: 12), "Chapter 2")
    }

    func testReaderHighlightsEveryParagraphOfAPassage() throws {
        let (app, ids) = try makeApp(books: [("Passages", 80)])
        let book = try XCTUnwrap(app.store.feedBook(id: ids[0]))
        let passages = app.store.segments(book: book, style: .passage, from: 0, limit: 200)
        let wide = try XCTUnwrap(passages.first { passage in
            app.store.segmentsOverlapping(start: passage.charStart, end: passage.charEnd, book: book, style: .paragraph).count > 1
        }, "The fixture has a passage spanning paragraphs")
        let model = ContextReaderModel(store: app.store, book: book, charStart: wide.charStart, charEnd: wide.charEnd)
        let highlighted = model.paragraphs.filter(model.isHighlighted).map(\.index)
        let expected = app.store.segmentsOverlapping(start: wide.charStart, end: wide.charEnd, book: book, style: .paragraph).map(\.index)
        XCTAssertEqual(highlighted, expected)
    }

    func testOpenReaderAndContinueInFeed() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 60), ("Beta", 60)])
        let post = try XCTUnwrap(app.feed.posts.first)
        app.openReader(for: post)
        let model = try XCTUnwrap(app.readerRequest?.model)
        XCTAssertEqual(model.book.id, post.bookID)

        let book = try XCTUnwrap(app.store.feedBook(id: ids[1]))
        let target = try XCTUnwrap(app.store.segments(book: book, style: .paragraph, from: 30, limit: 1).first)
        app.selectedTab = .saved
        app.continueInFeed(bookID: ids[1], offset: target.charStart)

        XCTAssertNil(app.readerRequest)
        XCTAssertEqual(app.selectedTab, .feed)
        XCTAssertEqual(app.store.book(id: ids[1])?.positionOffset, target.charStart)
        XCTAssertEqual(app.feed.posts.first?.bookID, ids[1])
        XCTAssertEqual(app.feed.posts.first?.segment.index, 30)
        XCTAssertEqual(app.feed.scrolledID, app.feed.posts.first?.id)
    }

    // MARK: Marks and Saved

    func testLikeAndBookmarkToggleAndShowInSaved() throws {
        let (app, _) = try makeApp(books: [("Alpha", 40)])
        let posts = Array(app.feed.posts.prefix(3))
        XCTAssertEqual(posts.count, 3)

        app.marks.toggle(.like, posts[0])
        app.marks.toggle(.bookmark, posts[1])
        app.marks.toggle(.like, posts[2])
        XCTAssertTrue(app.marks.isMarked(.like, posts[0]))
        XCTAssertFalse(app.marks.isMarked(.bookmark, posts[0]))
        XCTAssertTrue(app.marks.isMarked(.bookmark, posts[1]))
        XCTAssertEqual(app.store.allMarks().count, 3, "Marks are saved")

        XCTAssertEqual(app.savedPosts(filter: .all, style: .paragraph).map(\.id), [posts[2].id, posts[1].id, posts[0].id], "Newest first")
        XCTAssertEqual(app.savedPosts(filter: .liked, style: .paragraph).map(\.id), [posts[2].id, posts[0].id])
        XCTAssertEqual(app.savedPosts(filter: .bookmarked, style: .paragraph).map(\.id), [posts[1].id])
        XCTAssertTrue(app.savedPosts(filter: .all, style: .paragraph).allSatisfy(\.showsThreadButton))

        // In Passages style the same marks show as the passages that overlap them.
        let passages = app.savedPosts(filter: .liked, style: .passage)
        XCTAssertFalse(passages.isEmpty)
        XCTAssertTrue(passages.allSatisfy { $0.segment.style == .passage && app.marks.isMarked(.like, $0) })

        app.marks.toggle(.like, posts[0])
        XCTAssertFalse(app.marks.isMarked(.like, posts[0]))
        XCTAssertEqual(app.store.allMarks().count, 2)

        // A fresh app (relaunch) reads the same marks.
        let relaunched = AppModel(container: app.container)
        XCTAssertTrue(relaunched.marks.isMarked(.like, posts[2]))
        XCTAssertTrue(relaunched.marks.isMarked(.bookmark, posts[1]))
        XCTAssertFalse(relaunched.marks.isMarked(.like, posts[0]))
    }

    // MARK: Delete

    func testDeleteHidesTheBookAtOnceAndRemovesItsRows() async throws {
        let (app, ids) = try makeApp(books: [("Keep", 30), ("Drop", 50)])
        let dropPost = try XCTUnwrap(app.feed.posts.first { $0.bookID == ids[1] })
        app.marks.toggle(.like, dropPost)
        XCTAssertEqual(app.savedPosts(filter: .all, style: .paragraph).count, 1)

        let task = app.deleteBook(id: ids[1])
        XCTAssertNotNil(task)
        XCTAssertEqual(app.feed.books.map(\.id), [ids[0]], "Gone from the feed before the rows are deleted")
        XCTAssertFalse(app.feed.posts.contains { $0.bookID == ids[1] })
        XCTAssertTrue(app.store.feedBooks().allSatisfy { $0.id != ids[1] }, "Gone from the Library")
        XCTAssertTrue(app.savedPosts(filter: .all, style: .paragraph).isEmpty, "Gone from Saved")
        XCTAssertNil(app.deleteBook(id: ids[1]), "A second swipe does nothing")

        _ = await task?.value
        XCTAssertEqual(try Fixtures.segmentCount(bookID: ids[1], in: app.container), 0)
        XCTAssertGreaterThan(try Fixtures.segmentCount(bookID: ids[0], in: app.container), 0)
        XCTAssertTrue(app.store.allMarks().isEmpty)
        XCTAssertNil(app.errorMessage)
        XCTAssertEqual(app.libraryVersion, 1)
    }

    func testAnInterruptedDeletionFinishesAtLaunch() async throws {
        let container = try Fixtures.makeContainer()
        let keep = try Fixtures.writeBook(title: "Keep", paragraphs: 20, into: ModelContext(container))
        let drop = try Fixtures.writeBook(title: "Drop", paragraphs: 20, seed: 2, into: ModelContext(container))
        // The app stopped after hiding the book, before its rows were deleted.
        LibraryStore(context: ModelContext(container)).markForDeletion(id: drop)

        let app = AppModel(container: container)
        XCTAssertEqual(app.resumedDeletions.count, 1)
        for task in app.resumedDeletions { await task.value }
        XCTAssertEqual(try Fixtures.segmentCount(bookID: drop, in: container), 0)
        XCTAssertEqual(app.store.feedBooks().map(\.id), [keep])
        XCTAssertTrue(BookDeleter.pendingBookIDs(in: ModelContext(container)).isEmpty)
    }

    func testDeletingTheOneBookInOneBookModeFallsBackToMix() async throws {
        let (app, ids) = try makeApp(books: [("Keep", 30), ("Drop", 30)])
        app.feed.configure(style: .paragraph, mode: .single(ids[1]))
        XCTAssertEqual(app.feed.title, "Drop")
        XCTAssertTrue(app.feed.posts.allSatisfy { $0.bookID == ids[1] })

        _ = await app.deleteBook(id: ids[1])?.value
        XCTAssertEqual(app.feed.mode, .mix)
        XCTAssertEqual(app.feed.title, "Feed")
        XCTAssertFalse(app.feed.posts.isEmpty)
        XCTAssertTrue(app.feed.posts.allSatisfy { $0.bookID == ids[0] })
    }

    // MARK: Feed position

    func testScrollingSavesPositionsOnlyForShownPosts() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 80)])
        app.feed.configure(style: .paragraph, mode: .single(ids[0]))
        let posts = app.feed.posts
        XCTAssertGreaterThan(posts.count, 12)

        app.feed.didScroll(to: posts[10].id)
        XCTAssertEqual(app.store.book(id: ids[0])?.positionOffset, posts[10].segment.charStart)
        app.feed.didScroll(to: posts[4].id)
        XCTAssertEqual(app.store.book(id: ids[0])?.positionOffset, posts[10].segment.charStart, "Scrolling back never moves the position back")

        // Switching style resumes at the passage that holds the saved offset.
        app.feed.configure(style: .passage, mode: .single(ids[0]))
        let first = try XCTUnwrap(app.feed.posts.first)
        XCTAssertTrue(first.segment.contains(offset: posts[10].segment.charStart))
    }
}
