import SwiftData
import UIKit
import XCTest
@testable import Bookscroll

/// Word limit (split posts), chapter-start posts, the automatic limit, the chapter table and
/// the Mix filters (hide, snooze, weight).
final class SplitAndFilterTests: XCTestCase {
    private func makeLibrary(bookCount: Int, paragraphs: Int, chapterEvery: Int = 10) -> (InMemorySegmentSource, [FeedBook]) {
        let source = InMemorySegmentSource()
        var books: [FeedBook] = []
        for i in 0..<bookCount {
            let id = UUID()
            let segmented = Segmenter.segment(Fixtures.paragraphs(count: paragraphs, chapterEvery: chapterEvery, seed: i + 3))
            source.add(bookID: id, segmented: segmented)
            books.append(Fixtures.feedBook(id: id, ordinal: i + 1, title: "Book \(i)", segmented: segmented))
        }
        return (source, books)
    }

    private func drain(_ engine: FeedEngine, limit: Int = 5000) -> [FeedPost] {
        var guardCount = 0
        while !engine.isAtEnd && guardCount < limit {
            engine.loadMore()
            guardCount += 1
        }
        return engine.posts
    }

    // MARK: Splitter

    func testShortTextIsOnePart() {
        let text = "One short sentence. And another."
        XCTAssertEqual(PostSplitter.parts(of: text, limit: 10), [0..<(text as NSString).length])
        XCTAssertEqual(PostSplitter.parts(of: text, limit: 0), [0..<(text as NSString).length], "0 means no limit")
    }

    func testPartsTakeWholeSentencesUpToTheLimit() {
        let text = "One two three four. Five six seven. Eight nine ten eleven twelve. Thirteen."
        let parts = PostSplitter.parts(of: text, limit: 8)
        let strings = parts.map { (text as NSString).substring(with: NSRange($0)) }
        XCTAssertEqual(strings, ["One two three four. Five six seven. ", "Eight nine ten eleven twelve. Thirteen."])
        assertTiles(parts, length: (text as NSString).length)
    }

    func testOverLongSentenceIsCutBetweenWords() {
        let words = (1...25).map { "w\($0)" }
        let text = words.joined(separator: " ") + "."
        let parts = PostSplitter.parts(of: text, limit: 10)
        let counts = parts.map { TextUtils.wordCount((text as NSString).substring(with: NSRange($0))) }
        XCTAssertEqual(counts, [10, 10, 5])
        assertTiles(parts, length: (text as NSString).length)
        XCTAssertTrue((text as NSString).substring(with: NSRange(parts[1])).hasPrefix("w11 "))
    }

    func testEveryPartIsWithinTheLimitOnFixtureText() {
        for paragraph in Fixtures.paragraphs(count: 60, seed: 7) {
            for limit in [12, 20, 40, 80] {
                let parts = PostSplitter.parts(of: paragraph.text, limit: limit)
                assertTiles(parts, length: (paragraph.text as NSString).length)
                for part in parts {
                    let words = TextUtils.wordCount((paragraph.text as NSString).substring(with: NSRange(part)))
                    XCTAssertLessThanOrEqual(words, limit)
                    XCTAssertGreaterThan(words, 0)
                }
            }
        }
    }

    private func assertTiles(_ parts: [Range<Int>], length: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(parts.first?.lowerBound, 0, file: file, line: line)
        XCTAssertEqual(parts.last?.upperBound, length, file: file, line: line)
        for (a, b) in zip(parts, parts.dropFirst()) {
            XCTAssertEqual(a.upperBound, b.lowerBound, "Parts are contiguous", file: file, line: line)
        }
    }

    // MARK: Word limit setting

    func testWordLimitStorageAndPerBookLimit() {
        for limit in WordLimit.choices {
            XCTAssertEqual(WordLimit(storage: limit.storage), limit)
        }
        var book = Fixtures.feedBook(id: UUID(), ordinal: 1, title: "B", segmented: Segmenter.segment(Fixtures.paragraphs(count: 3)))
        XCTAssertNil(WordLimit.auto.limit(for: book), "No limit until the book's value is computed")
        book.autoWordLimit = 73
        XCTAssertEqual(WordLimit.auto.limit(for: book), 73)
        XCTAssertNil(WordLimit.off.limit(for: book))
        XCTAssertEqual(WordLimit.words(60).limit(for: book), 60)
    }

    // MARK: Engine with a word limit

    func testSplitPostsTileTheBookInOrder() throws {
        let (source, books) = makeLibrary(bookCount: 1, paragraphs: 50)
        let book = books[0]
        let engine = FeedEngine(source: source, books: [book], style: .paragraph, mode: .single(book.id), seed: 1, wordLimit: .words(25))
        let posts = drain(engine)
        XCTAssertGreaterThan(posts.count, 50, "Long paragraphs became several posts")
        XCTAssertEqual(posts.first?.segment.charStart, 0)
        XCTAssertEqual(posts.last?.segment.charEnd, book.totalCharacters)
        for (a, b) in zip(posts, posts.dropFirst()) {
            XCTAssertEqual(a.segment.charEnd, b.segment.charStart, "Posts tile the text")
        }
        XCTAssertEqual(Set(posts.map(\.id)).count, posts.count, "Unique ids")
        for post in posts {
            XCTAssertLessThanOrEqual(TextUtils.wordCount(post.segment.text), 25)
            if post.partCount > 1 {
                XCTAssertTrue(post.progressLine.hasSuffix("\(post.part)/\(post.partCount)"))
            }
        }
        // Parts of one paragraph form a thread in One book mode.
        let split = try XCTUnwrap(posts.firstIndex { $0.part == 2 })
        XCTAssertTrue(posts[split].continuesThread)
        XCTAssertTrue(posts[split - 1].threadContinuesBelow)
    }

    func testResumingInsideASplitParagraphStartsAtTheRightPart() throws {
        let (source, books) = makeLibrary(bookCount: 1, paragraphs: 40)
        var book = books[0]
        let first = FeedEngine(source: source, books: [book], style: .paragraph, mode: .single(book.id), seed: 1, wordLimit: .words(15))
        let all = drain(first)
        let target = try XCTUnwrap(all.first { $0.part == 2 && $0.segment.index > 3 })
        _ = first.markShown(through: target.id)
        XCTAssertEqual(first.books[book.id]?.positionOffset, target.segment.charStart)

        // A new session (relaunch) at the saved position shows the same part first.
        book.positionOffset = target.segment.charStart
        let second = FeedEngine(source: source, books: [book], style: .paragraph, mode: .single(book.id), seed: 1, wordLimit: .words(15))
        second.loadMore()
        XCTAssertEqual(second.posts.first?.id, target.id)

        // In the same session, a refresh continues after the last part shown.
        first.refresh(seed: 2)
        let next = try XCTUnwrap(all.firstIndex { $0.id == target.id }).advanced(by: 1)
        XCTAssertEqual(first.posts.first?.id, all[next].id)
    }

    // MARK: Chapter starts

    func testChapterStartIsMarkedOnTheFirstPostOfEachChapter() {
        let (source, books) = makeLibrary(bookCount: 1, paragraphs: 35, chapterEvery: 10)
        let book = books[0]
        let engine = FeedEngine(source: source, books: [book], style: .paragraph, mode: .mix, seed: 1, wordLimit: .words(20))
        let posts = drain(engine)
        let starts = posts.filter(\.startsChapter)
        XCTAssertEqual(starts.map(\.segment.chapter), ["Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4"])
        XCTAssertTrue(starts.allSatisfy { $0.part == 1 })
        XCTAssertEqual(starts.map(\.segment.index), [0, 10, 20, 30])
    }

    func testResumingMidChapterIsNotAChapterStartButResumingAtOneIs() {
        let (source, books) = makeLibrary(bookCount: 1, paragraphs: 30, chapterEvery: 10)
        var book = books[0]
        let paragraphs = source.segments(book: book, style: .paragraph, from: 0, limit: 30)
        book.positionOffset = paragraphs[14].charStart
        let midChapter = FeedEngine(source: source, books: [book], style: .paragraph, mode: .mix, seed: 1)
        midChapter.loadMore(1)
        XCTAssertFalse(midChapter.posts[0].startsChapter)

        book.positionOffset = paragraphs[20].charStart
        let atStart = FeedEngine(source: source, books: [book], style: .paragraph, mode: .mix, seed: 1)
        atStart.loadMore(1)
        XCTAssertTrue(atStart.posts[0].startsChapter)

        // One book mode: the chapter row says it is a new chapter.
        let single = FeedEngine(source: source, books: [book], style: .paragraph, mode: .single(book.id), seed: 1)
        single.loadMore(1)
        XCTAssertEqual(single.posts[0].chapterHeader, "Chapter 3")
        XCTAssertTrue(single.posts[0].startsChapter)
    }

    // MARK: Mix filters

    func testHiddenAndSnoozedBooksAreLeftOutOfMixOnly() {
        let (source, books) = makeLibrary(bookCount: 3, paragraphs: 20)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var library = books
        library[0].hiddenFromMix = true
        library[1].snoozedUntil = now.addingTimeInterval(3600)
        let mix = FeedEngine(source: source, books: library, style: .paragraph, mode: .mix, seed: 4, now: { now })
        let posts = drain(mix)
        XCTAssertEqual(Set(posts.map(\.bookID)), [library[2].id])

        // A snooze that has ended no longer applies.
        let later = FeedEngine(source: source, books: library, style: .paragraph, mode: .mix, seed: 4, now: { now.addingTimeInterval(7200) })
        XCTAssertEqual(Set(drain(later).map(\.bookID)), [library[1].id, library[2].id])

        // One book mode ignores the filters.
        let single = FeedEngine(source: source, books: library, style: .paragraph, mode: .single(library[0].id), seed: 4, now: { now })
        single.loadMore()
        XCTAssertFalse(single.posts.isEmpty)
    }

    func testHidingABookRemovesItsUnseenPostsButKeepsShownOnes() throws {
        let (source, books) = makeLibrary(bookCount: 2, paragraphs: 30)
        let engine = FeedEngine(source: source, books: books, style: .paragraph, mode: .mix, seed: 8)
        engine.loadMore(20)
        let firstOfHidden = try XCTUnwrap(engine.posts.firstIndex { $0.bookID == books[0].id })
        _ = engine.markShown(through: engine.posts[firstOfHidden].id)
        var updated = books
        updated[0].hiddenFromMix = true
        engine.updateBooks(updated)
        let remaining = engine.posts.enumerated().filter { $0.element.bookID == books[0].id }.map(\.offset)
        XCTAssertTrue(remaining.allSatisfy { $0 <= firstOfHidden }, "Only posts already shown remain")
        engine.loadMore(40)
        XCTAssertTrue(engine.posts.dropFirst(firstOfHidden + 1).allSatisfy { $0.bookID == books[1].id })
        for (n, post) in engine.posts.enumerated() {
            XCTAssertEqual(engine.index(ofPost: post.id), n)
        }
    }

    func testWeightsChangeHowOftenMixPicksABook() {
        let (source, books) = makeLibrary(bookCount: 2, paragraphs: 400)
        var weighted = books
        weighted[0].feedWeight = 2
        weighted[1].feedWeight = 0.5
        let engine = FeedEngine(source: source, books: weighted, style: .paragraph, mode: .mix, seed: 11)
        engine.loadMore(300)
        let heavy = engine.posts.filter { $0.bookID == books[0].id }.count
        let light = engine.posts.count - heavy
        // Expected ratio 4:1; allow a wide band for randomness.
        XCTAssertGreaterThan(Double(heavy) / Double(max(light, 1)), 2.5, "\(heavy) vs \(light)")
    }

    // MARK: Derived data

    func testAutoWordLimitFitsNinetyFivePercent() {
        XCTAssertEqual(DerivedData.wordLimit(wordCounts: Array(1...100)), 95)
        XCTAssertEqual(DerivedData.wordLimit(wordCounts: Array(repeating: 10, count: 50)), DerivedData.minimumWordLimit, "Never below the minimum")
        XCTAssertEqual(DerivedData.wordLimit(wordCounts: []), DerivedData.minimumWordLimit)
        let counts = (0..<200).map { 30 + ($0 * 37) % 170 }
        let limit = DerivedData.wordLimit(wordCounts: counts)
        let fitting = counts.filter { $0 <= limit }.count
        XCTAssertGreaterThanOrEqual(Double(fitting) / Double(counts.count), 0.95)
        XCTAssertLessThan(Double(counts.filter { $0 < limit }.count) / Double(counts.count), 0.95, "It is the smallest such limit")
    }

    func testChapterTableListsEachChapterOnce() {
        var builder = DerivedData.Builder()
        let chapters = ["", "", "One", "One", "Two", "", "Three"]
        for (n, chapter) in chapters.enumerated() {
            builder.add(index: n, charStart: n * 10, chapter: chapter, text: "word")
        }
        XCTAssertEqual(builder.chapters, [
            ChapterEntry(title: "One", index: 2, charStart: 20),
            ChapterEntry(title: "Two", index: 4, charStart: 40),
            ChapterEntry(title: "Three", index: 6, charStart: 60),
        ])
        XCTAssertEqual(DerivedData.decode(DerivedData.encode(builder.chapters)), builder.chapters)
        XCTAssertEqual(DerivedData.decode(nil), [])
    }

    func testImportComputesDerivedDataAndBackfillHandlesOlderBooks() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let id = try Fixtures.writeBook(title: "Derived", paragraphs: 45, chapterEvery: 10, into: context)
        let book = try XCTUnwrap(context.fetch(FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(book.derivedVersion, DerivedData.currentVersion)
        XCTAssertGreaterThanOrEqual(book.autoWordLimit, DerivedData.minimumWordLimit)
        let chapters = DerivedData.decode(book.chapterTable)
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3", "Chapter 4", "Chapter 5"])
        XCTAssertEqual(chapters.map(\.index), [0, 10, 20, 30, 40])
        let expected = (book.autoWordLimit, book.chapterTable)

        // A book from before version 2: the backfill computes the same values.
        book.derivedVersion = 0
        book.autoWordLimit = 0
        book.chapterTable = nil
        try context.save()
        let results = try DerivedDataBackfill.compute(container: container, batchSize: 7)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.wordLimit, expected.0)
        XCTAssertEqual(DerivedData.decode(results.first?.chapterTable), DerivedData.decode(expected.1))
        let store = LibraryStore(context: context)
        XCTAssertTrue(store.applyDerived(results))
        XCTAssertEqual(store.chapters(bookID: id).count, 5)
        XCTAssertTrue(try DerivedDataBackfill.compute(container: container).isEmpty, "Nothing left to do")
    }

    // MARK: App

    @MainActor
    func testAppFeedFiltersAreStoredAndApplied() async throws {
        let container = try Fixtures.makeContainer()
        let first = try Fixtures.writeBook(title: "First", paragraphs: 30, seed: 1, into: ModelContext(container))
        let second = try Fixtures.writeBook(title: "Second", paragraphs: 30, seed: 2, into: ModelContext(container))
        let app = AppModel(container: container)
        await app.derivedBackfill?.value
        app.feed.configure(style: .paragraph, mode: .mix)

        app.setHiddenFromMix(true, bookID: first)
        XCTAssertEqual(app.store.book(id: first)?.hiddenFromMix, true)
        app.feed.refresh()
        XCTAssertTrue(app.feed.posts.allSatisfy { $0.bookID == second })

        app.setHiddenFromMix(false, bookID: first)
        let now = Date()
        app.snooze(bookID: second, days: 7, now: now)
        let until = try XCTUnwrap(app.store.book(id: second)?.snoozedUntil)
        XCTAssertEqual(until.timeIntervalSince(now), 7 * 24 * 3600, accuracy: 1)
        app.feed.refresh()
        XCTAssertTrue(app.feed.posts.allSatisfy { $0.bookID == first })
        app.snooze(bookID: second, days: nil)
        XCTAssertNil(app.store.book(id: second)?.snoozedUntil)

        app.setFeedWeight(2, bookID: first)
        XCTAssertEqual(app.store.feedBook(id: first)?.feedWeight, 2)
        XCTAssertEqual(app.actions(for: try XCTUnwrap(app.feed.posts.first { $0.bookID == first })).bookFeedWeight, 2)
    }
}

/// Jump to, context peek and look up through the app model.
@MainActor
final class JumpAndPeekTests: XCTestCase {
    private func makeApp() throws -> (AppModel, UUID, UUID) {
        let container = try Fixtures.makeContainer()
        let first = try Fixtures.writeBook(title: "First", paragraphs: 50, chapterEvery: 10, seed: 1, into: ModelContext(container))
        let second = try Fixtures.writeBook(title: "Second", paragraphs: 30, seed: 2, into: ModelContext(container))
        let app = AppModel(container: container)
        app.feed.configure(style: .paragraph, mode: .mix)
        return (app, first, second)
    }

    func testJumpToAChapterOpensTheBookThere() throws {
        let (app, first, _) = try makeApp()
        let chapters = app.store.chapters(bookID: first)
        XCTAssertEqual(chapters.count, 5)
        app.selectedTab = .library
        app.jump(bookID: first, offset: chapters[3].charStart)
        XCTAssertEqual(app.selectedTab, .feed)
        XCTAssertEqual(app.feed.mode, .single(first))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "feedMode"), "single")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "singleBookID"), first.uuidString)
        let top = try XCTUnwrap(app.feed.posts.first)
        XCTAssertEqual(top.segment.charStart, chapters[3].charStart)
        XCTAssertEqual(top.segment.chapter, "Chapter 4")
        XCTAssertTrue(top.startsChapter)
        XCTAssertEqual(app.store.book(id: first)?.positionOffset, chapters[3].charStart, "The jump is saved")

        // Jumping back to the start is allowed (it is an explicit request).
        app.jump(bookID: first, offset: 0)
        XCTAssertEqual(app.feed.posts.first?.segment.index, 0)
        XCTAssertEqual(app.store.book(id: first)?.positionOffset, 0)
        UserDefaults.standard.removeObject(forKey: "feedMode")
        UserDefaults.standard.removeObject(forKey: "singleBookID")
    }

    func testPeekShowsTwoParagraphsEachSide() throws {
        let (app, first, _) = try makeApp()
        let book = try XCTUnwrap(app.store.feedBook(id: first))
        let segment = try XCTUnwrap(app.store.segments(book: book, style: .paragraph, from: 20, limit: 1).first)
        let post = FeedPost(segment: segment, book: book, showsThreadButton: true)
        let peek = try XCTUnwrap(app.peek(for: post))
        XCTAssertEqual(peek.before.map(\.index), [18, 19])
        XCTAssertEqual(peek.post.map(\.index), [20])
        XCTAssertEqual(peek.after.map(\.index), [21, 22])
        XCTAssertEqual(peek.highlight, segment.charStart..<segment.charEnd)

        // At the start of the book there is nothing before.
        let opening = try XCTUnwrap(app.store.segments(book: book, style: .paragraph, from: 0, limit: 1).first)
        XCTAssertEqual(app.peek(for: FeedPost(segment: opening, book: book, showsThreadButton: true))?.before, [])

        // A passage covers several paragraphs; all of them are highlighted.
        let passages = app.store.segments(book: book, style: .passage, from: 0, limit: 100)
        let wide = try XCTUnwrap(passages.first { app.store.segmentsOverlapping(start: $0.charStart, end: $0.charEnd, book: book, style: .paragraph).count > 1 })
        let widePeek = try XCTUnwrap(app.peek(for: FeedPost(segment: wide, book: book, showsThreadButton: true)))
        XCTAssertGreaterThan(widePeek.post.count, 1)
    }

    func testPostActionsReachTheModel() throws {
        let (app, first, _) = try makeApp()
        let post = try XCTUnwrap(app.feed.posts.first { $0.bookID == first })
        let actions = app.actions(for: post)
        XCTAssertNotNil(actions.peek())
        actions.lookUp()
        XCTAssertEqual(app.lookUpPost?.id, post.id)
        actions.copy(true)
        XCTAssertEqual(UIPasteboard.general.string, ShareFormatter.citation(post))
        actions.continueHere()
        XCTAssertEqual(app.store.book(id: first)?.positionOffset, post.segment.charStart)
        app.presentJump(bookID: first)
        XCTAssertEqual(app.jumpRequest?.bookID, first)
    }
}
