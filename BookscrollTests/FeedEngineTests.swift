import XCTest
@testable import Bookscroll

final class FeedEngineTests: XCTestCase {
    private struct Library {
        let source: InMemorySegmentSource
        let books: [FeedBook]
        let segmented: [UUID: SegmentedBook]
    }

    private func makeLibrary(bookCount: Int, paragraphs: Int, chapterEvery: Int = 10) -> Library {
        let source = InMemorySegmentSource()
        var books: [FeedBook] = []
        var segmented: [UUID: SegmentedBook] = [:]
        for i in 0..<bookCount {
            let id = UUID()
            let book = Segmenter.segment(Fixtures.paragraphs(count: paragraphs, chapterEvery: chapterEvery, seed: i + 3))
            source.add(bookID: id, segmented: book)
            segmented[id] = book
            books.append(Fixtures.feedBook(id: id, ordinal: i + 1, title: "Book \(i)", segmented: book))
        }
        return Library(source: source, books: books, segmented: segmented)
    }

    func testMixHasNoRepeatsAndNeverStalls() {
        let library = makeLibrary(bookCount: 3, paragraphs: 40)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .mix, seed: 42)
        var shownOverSession: [String] = []
        var refreshed = false
        var guardCounter = 0
        engine.loadMore()
        while !(engine.isAtEnd && engine.posts.allSatisfy { shownOverSession.contains($0.id) }) {
            guardCounter += 1
            XCTAssertLessThan(guardCounter, 1000, "Feed stalled")
            if guardCounter >= 1000 { break }

            // Scroll: the top visible post moves down by 7 posts at a time.
            let alreadyShown = Set(shownOverSession)
            let target = min(engine.posts.count - 1, (engine.posts.firstIndex { !alreadyShown.contains($0.id) } ?? engine.posts.count - 1) + 6)
            for post in engine.posts[0...target] where !alreadyShown.contains(post.id) {
                shownOverSession.append(post.id)
            }
            engine.markShown(through: engine.posts[target].id)
            if target >= engine.posts.count - 12 { engine.loadMore() }

            if !refreshed && shownOverSession.count > 40 {
                refreshed = true
                engine.refresh(seed: 7)
                XCTAssertTrue(Set(engine.posts.map(\.id)).isDisjoint(with: shownOverSession), "Refresh brought back a post already shown")
            }
        }
        XCTAssertTrue(refreshed)
        XCTAssertEqual(shownOverSession.count, Set(shownOverSession).count, "A post was shown twice")
        XCTAssertEqual(engine.posts.count, Set(engine.posts.map(\.id)).count, "The list holds a post twice")
        XCTAssertEqual(Set(shownOverSession).count, 120, "Every paragraph of every book was reached")
        XCTAssertTrue(engine.isAtEnd)
        XCTAssertEqual(engine.shownIDs, Set(shownOverSession))
    }

    func testMixInterleavesBooksAndContinuesFromEachPosition() {
        var library = makeLibrary(bookCount: 4, paragraphs: 30)
        var books = library.books
        let positions = [0, 10, 20, 5]
        for i in books.indices {
            let segments = library.segmented[books[i].id]!.paragraphs
            books[i].positionOffset = segments[positions[i]].charStart + 3
        }
        library = Library(source: library.source, books: books, segmented: library.segmented)
        let engine = FeedEngine(source: library.source, books: books, style: .paragraph, mode: .mix, seed: 1)
        engine.loadMore(60)
        XCTAssertEqual(Set(engine.posts.map(\.bookID)).count, 4, "All books appear in the mix")
        for (i, book) in books.enumerated() {
            let indices = engine.posts.filter { $0.bookID == book.id }.map(\.segment.index)
            XCTAssertEqual(indices.first, positions[i], "Book \(i) starts at its own position")
            XCTAssertEqual(indices, Array(positions[i]..<(positions[i] + indices.count)), "Book \(i) goes in order")
        }
        XCTAssertTrue(engine.posts.allSatisfy(\.showsThreadButton))
        XCTAssertTrue(engine.posts.allSatisfy { !$0.continuesThread && $0.chapterHeader == nil })
    }

    func testPositionAdvancesOnlyWhenShown() {
        let library = makeLibrary(bookCount: 3, paragraphs: 30)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .mix, seed: 9)
        engine.loadMore()
        XCTAssertEqual(engine.posts.count, FeedEngine.pageSize)
        for book in library.books {
            XCTAssertEqual(engine.books[book.id]?.positionOffset, 0, "Loading must not move positions")
        }

        let target = 8
        let updates = engine.markShown(through: engine.posts[target].id)
        var expected: [UUID: Int] = [:]
        for post in engine.posts[0...target] where post.segment.charStart > 0 {
            expected[post.bookID] = max(expected[post.bookID] ?? 0, post.segment.charStart)
        }
        XCTAssertEqual(updates, expected)
        for book in library.books {
            XCTAssertEqual(engine.books[book.id]?.positionOffset, expected[book.id] ?? 0)
        }

        // Loading more does not move positions; marking the same post again changes nothing.
        engine.loadMore()
        XCTAssertTrue(engine.markShown(through: engine.posts[target].id).isEmpty)
        XCTAssertTrue(engine.markShown(through: engine.posts[3].id).isEmpty, "Scrolling back up never moves a position back")
    }

    func testSingleBookModeStaysInOneBook() {
        let library = makeLibrary(bookCount: 3, paragraphs: 45)
        let chosen = library.books[1]
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .single(chosen.id), seed: 3)
        while !engine.isAtEnd { engine.loadMore() }
        XCTAssertEqual(engine.posts.count, 45)
        XCTAssertTrue(engine.posts.allSatisfy { $0.bookID == chosen.id })
        XCTAssertEqual(engine.posts.map(\.segment.index), Array(0..<45))
        XCTAssertTrue(engine.posts.allSatisfy { !$0.showsThreadButton })
    }

    func testSingleBookModeUsesPassagesWhenForced() {
        let library = makeLibrary(bookCount: 1, paragraphs: 30)
        let original = library.books[0]
        let forced = FeedBook(
            id: original.id, ordinal: 1, title: original.title, author: original.author,
            totalCharacters: original.totalCharacters, positionOffset: 0, passagesOnly: true,
            paragraphCount: original.paragraphCount, passageCount: original.passageCount
        )
        let engine = FeedEngine(source: library.source, books: [forced], style: .paragraph, mode: .single(forced.id), seed: 1)
        engine.loadMore()
        XCTAssertTrue(engine.posts.allSatisfy { $0.segment.style == .passage })
    }

    func testThreadsBreakAtChapterChanges() {
        let library = makeLibrary(bookCount: 1, paragraphs: 9, chapterEvery: 3)
        let book = library.books[0]
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .single(book.id), seed: 1)
        engine.loadMore()
        let posts = engine.posts
        XCTAssertEqual(posts.count, 9)
        XCTAssertEqual(posts.map(\.segment.chapter), [
            "Chapter 1", "Chapter 1", "Chapter 1",
            "Chapter 2", "Chapter 2", "Chapter 2",
            "Chapter 3", "Chapter 3", "Chapter 3",
        ])
        XCTAssertEqual(posts.map(\.continuesThread), [false, true, true, false, true, true, false, true, true])
        XCTAssertEqual(posts.map(\.threadContinuesBelow), [true, true, false, true, true, false, true, true, false])
        XCTAssertEqual(posts.map(\.chapterHeader), ["Chapter 1", nil, nil, "Chapter 2", nil, nil, "Chapter 3", nil, nil])
    }

    func testResumeStartsAtPostContainingPosition() {
        let library = makeLibrary(bookCount: 1, paragraphs: 30)
        var book = library.books[0]
        let paragraphs = library.segmented[book.id]!.paragraphs
        book.positionOffset = paragraphs[17].charStart + 11
        let engine = FeedEngine(source: library.source, books: [book], style: .paragraph, mode: .single(book.id), seed: 1)
        engine.loadMore()
        XCTAssertEqual(engine.posts.first?.segment.index, 17)
        XCTAssertEqual(engine.posts.first?.chapterHeader, "Chapter 2", "The first post always shows its chapter")
    }

    func testJumpRestartsBookFromOffset() {
        let library = makeLibrary(bookCount: 2, paragraphs: 30)
        let book = library.books[0]
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .mix, seed: 5)
        engine.loadMore()
        engine.markShown(through: engine.posts[20].id)
        let paragraphs = library.segmented[book.id]!.paragraphs
        engine.resetBook(book.id, offset: paragraphs[2].charStart)
        engine.refresh(seed: 6, leadingBook: book.id)
        XCTAssertEqual(engine.posts.first?.bookID, book.id)
        XCTAssertEqual(engine.posts.first?.segment.index, 2)
        XCTAssertEqual(engine.posts.count, Set(engine.posts.map(\.id)).count)
    }

    func testUpdateBooksAddsAndRemoves() {
        let library = makeLibrary(bookCount: 3, paragraphs: 20)
        let engine = FeedEngine(source: library.source, books: Array(library.books.prefix(2)), style: .paragraph, mode: .mix, seed: 2)
        engine.loadMore()
        let removed = library.books[0]
        engine.updateBooks([library.books[1], library.books[2]])
        XCTAssertFalse(engine.posts.contains { $0.bookID == removed.id })
        engine.loadMore(40)
        XCTAssertTrue(engine.posts.contains { $0.bookID == library.books[2].id })
        XCTAssertFalse(engine.posts.contains { $0.bookID == removed.id })
        XCTAssertEqual(engine.posts.count, Set(engine.posts.map(\.id)).count)
    }

    func testFetchesInSmallBatches() {
        let library = makeLibrary(bookCount: 1, paragraphs: 100)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .mix, seed: 2)
        engine.loadMore(30)
        XCTAssertEqual(library.source.fetchCount, 2, "30 posts come from two batches of \(FeedEngine.fetchBatchSize)")
    }

    func testProgressLine() {
        let library = makeLibrary(bookCount: 1, paragraphs: 20)
        let engine = FeedEngine(source: library.source, books: library.books, style: .paragraph, mode: .mix, seed: 2)
        engine.loadMore()
        let post = engine.posts[10]
        XCTAssertEqual(post.progressLine, "Chapter 2 \u{00B7} \(TextUtils.percent(post.segment.charStart, of: library.books[0].totalCharacters))%")
        XCTAssertEqual(ShareFormatter.quote(post), "\u{201C}\(post.segment.text)\u{201D}\n\nBook 0 by Author 1")
    }
}
