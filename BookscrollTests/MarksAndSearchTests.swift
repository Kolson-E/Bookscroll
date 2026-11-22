import SwiftData
import UIKit
import XCTest
@testable import Bookscroll

/// Highlights, the Saved lists, Library search and share cards.
@MainActor
final class MarksAndSearchTests: XCTestCase {
    private func makeApp(books: [(String, Int)], searchIndex: SearchIndex? = nil) throws -> (AppModel, [UUID]) {
        let container = try Fixtures.makeContainer()
        var ids: [UUID] = []
        for (n, book) in books.enumerated() {
            ids.append(try Fixtures.writeBook(title: book.0, paragraphs: book.1, chapterEvery: 12, seed: n + 1, into: ModelContext(container)))
        }
        let app = AppModel(container: container, searchIndex: searchIndex)
        app.feed.configure(style: .paragraph, mode: .mix)
        return (app, ids)
    }

    private func paragraph(_ app: AppModel, _ bookID: UUID, _ index: Int) throws -> SegmentRecord {
        let book = try XCTUnwrap(app.store.feedBook(id: bookID))
        return try XCTUnwrap(app.store.segments(book: book, style: .paragraph, from: index, limit: 1).first)
    }

    // MARK: Highlights

    func testHighlightingASelectionStoresTheExactRange() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 30)])
        let target = try paragraph(app, ids[0], 4)
        let mark = try XCTUnwrap(app.marks.addHighlight(bookID: ids[0], start: target.charStart + 4, end: target.charStart + 20))
        XCTAssertEqual(mark.kind, .highlight)
        XCTAssertEqual(mark.charStart, target.charStart + 4)
        XCTAssertEqual(mark.charEnd, target.charStart + 20)

        XCTAssertEqual(app.marks.highlightRanges(bookID: ids[0], start: target.charStart, end: target.textEnd), [NSRange(location: 4, length: 16)])
        XCTAssertTrue(app.marks.highlightRanges(bookID: ids[0], start: target.textEnd + 1, end: target.textEnd + 50).isEmpty)

        let items = app.highlights()
        XCTAssertEqual(items.count, 1)
        let expected = (target.text as NSString).substring(with: NSRange(location: 4, length: 16)).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(items[0].text, expected)
        XCTAssertEqual(items[0].bookTitle, "Alpha")
        XCTAssertEqual(items[0].chapter, target.chapter)

        // Likes and bookmarks do not see highlights, and highlights survive a relaunch.
        let post = try XCTUnwrap(app.feed.posts.first)
        XCTAssertFalse(app.marks.isMarked(.like, post))
        let relaunched = AppModel(container: app.container)
        XCTAssertEqual(relaunched.highlights().map(\.text), [expected])
    }

    func testOverlappingAndTouchingHighlightsMerge() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 30)])
        let target = try paragraph(app, ids[0], 2)
        let base = target.charStart
        app.marks.addHighlight(bookID: ids[0], start: base + 10, end: base + 20)
        app.marks.addHighlight(bookID: ids[0], start: base + 15, end: base + 30)
        app.marks.addHighlight(bookID: ids[0], start: base + 30, end: base + 35)
        app.marks.addHighlight(bookID: ids[0], start: base + 50, end: base + 55)

        let ranges = app.marks.highlightRanges(bookID: ids[0], start: base, end: target.textEnd)
        XCTAssertEqual(ranges, [NSRange(location: 10, length: 25), NSRange(location: 50, length: 5)])
        XCTAssertEqual(app.store.allMarks().filter { $0.kind == .highlight }.count, 2, "Merged in the store too")

        // Removing with a selection inside the first highlight removes all of it.
        app.marks.removeHighlights(bookID: ids[0], start: base + 12, end: base + 13)
        XCTAssertEqual(app.marks.highlightRanges(bookID: ids[0], start: base, end: target.textEnd), [NSRange(location: 50, length: 5)])
        XCTAssertNil(app.marks.addHighlight(bookID: ids[0], start: base + 5, end: base + 5), "An empty selection is not a highlight")
    }

    func testHighlightAcrossParagraphsShowsBothParts() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 30)])
        let first = try paragraph(app, ids[0], 6)
        let second = try paragraph(app, ids[0], 7)
        app.marks.addHighlight(bookID: ids[0], start: first.textEnd - 10, end: second.charStart + 10)
        let item = try XCTUnwrap(app.highlights().first)
        let tail = (first.text as NSString).substring(from: (first.text as NSString).length - 10).trimmingCharacters(in: .whitespacesAndNewlines)
        let head = (second.text as NSString).substring(to: 10).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(item.text, "\(tail)\n\n\(head)")
        XCTAssertEqual(app.marks.highlightRanges(bookID: ids[0], start: second.charStart, end: second.textEnd), [NSRange(location: 0, length: 10)])
    }

    func testPostActionHighlightsTheWholePostAndRemovesIt() throws {
        let (app, _) = try makeApp(books: [("Alpha", 30)])
        let post = try XCTUnwrap(app.feed.posts.first)
        let actions = app.actions(for: post)
        actions.highlight()
        XCTAssertEqual(app.marks.highlightRanges(for: post), [NSRange(location: 0, length: (post.segment.text as NSString).length)])
        XCTAssertEqual(app.highlights().first?.text, post.segment.text)
        actions.highlight()
        XCTAssertTrue(app.marks.highlightRanges(for: post).isEmpty)
        XCTAssertTrue(app.highlights().isEmpty)
    }

    func testDeletingABookRemovesItsHighlights() async throws {
        let (app, ids) = try makeApp(books: [("Keep", 20), ("Drop", 20)])
        let kept = try paragraph(app, ids[0], 1)
        let dropped = try paragraph(app, ids[1], 1)
        app.marks.addHighlight(bookID: ids[0], start: kept.charStart, end: kept.textEnd)
        app.marks.addHighlight(bookID: ids[1], start: dropped.charStart, end: dropped.textEnd)
        await app.deleteBook(id: ids[1])?.value
        XCTAssertEqual(app.highlights().map(\.bookTitle), ["Keep"])
    }

    func testSavedFiltersMapToMarkKinds() {
        XCTAssertEqual(SavedFilter.allCases, [.bookmarked, .liked, .highlights], "Bookmarks come first")
        XCTAssertEqual(SavedFilter.allCases.map(\.kind), [.bookmark, .like, .highlight])
        XCTAssertEqual(SavedFilter.allCases.map(\.title), ["Bookmarks", "Likes", "Highlights"])
    }

    func testMarkerColoursKeepTextReadable() {
        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(PaletteHex.lightPrimary, PaletteHex.lightMarker), 7)
        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(PaletteHex.darkPrimary, PaletteHex.darkMarker), 7)
        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(PaletteHex.sepiaPrimary, PaletteHex.sepiaMarker), 7)
    }

    // MARK: Search

    func testSearchFindsParagraphsAndOpensTheReaderThere() async throws {
        let index = try SearchIndex.inMemory()
        let (app, ids) = try makeApp(books: [("Alpha", 40), ("Beta", 40)], searchIndex: index)
        await app.syncSearchIndex()?.value

        let target = try paragraph(app, ids[1], 17)
        let word = try XCTUnwrap(target.text.split(separator: " ").map(String.init).first { $0.count > 4 && $0.allSatisfy(\.isLetter) })
        let results = app.searchText(word)
        XCTAssertFalse(results.isEmpty)
        for result in results {
            let paragraph = try self.paragraph(app, result.bookID, result.index)
            XCTAssertEqual(result.charStart, paragraph.charStart)
            XCTAssertEqual(result.chapter, paragraph.chapter)
            XCTAssertTrue(paragraph.text.localizedCaseInsensitiveContains(word), "Every result contains the word")
            XCTAssertTrue(result.snippet.contains(SearchIndex.markStart), "The match is marked")
        }
        XCTAssertTrue(results.contains { $0.bookID == ids[1] && $0.index == 17 })
        XCTAssertEqual(Set(results.map(\.id)).count, results.count, "No duplicates")

        let hit = try XCTUnwrap(results.first)
        app.openReader(bookID: hit.bookID, charStart: hit.charStart, charEnd: hit.charEnd)
        let model = try XCTUnwrap(app.readerRequest?.model)
        XCTAssertEqual(model.anchorIndex, hit.index)

        XCTAssertTrue(app.searchText("").isEmpty)
        XCTAssertTrue(app.searchText("zzqqxx").isEmpty)
    }

    func testSearchWithoutAnIndexFindsNothing() throws {
        let (app, _) = try makeApp(books: [("Alpha", 10)])
        XCTAssertTrue(app.searchText("bridge").isEmpty)
    }

    func testSearchSkipsBooksThatAreBeingDeleted() async throws {
        let index = try SearchIndex.inMemory()
        let (app, ids) = try makeApp(books: [("Alpha", 30), ("Beta", 30)], searchIndex: index)
        await app.syncSearchIndex()?.value
        let task = app.deleteBook(id: ids[1])
        XCTAssertTrue(app.searchText("the").allSatisfy { $0.bookID == ids[0] }, "Hidden at once, before the index catches up")
        await task?.value
    }

    // MARK: Share cards

    func testEveryShareCardStyleAndThemeRenders() throws {
        let content = ShareCardContent(text: "The river ran fast under the old stone bridge.", title: "The Stone Bridge", author: "Ada Lane", chapter: "Chapter 2", percent: 42)
        XCTAssertEqual(content.source, "The Stone Bridge, Ada Lane \u{00B7} Chapter 2")
        for style in ShareCardStyle.allCases {
            for theme in ShareCardTheme.allCases {
                let image = try XCTUnwrap(ShareCardRenderer.image(for: content, style: style, theme: theme, accent: AccentChoice.blue.color), "\(style) \(theme)")
                XCTAssertEqual(image.size.width, 390, accuracy: 0.5)
                XCTAssertGreaterThan(image.size.height, 80)
                XCTAssertEqual(image.scale, 3)
            }
        }
    }

    func testShareCardThemesUseThePaletteAndKeepContrast() {
        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(PaletteHex.lightSecondary, PaletteHex.lightBackground), 4.5)
        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(PaletteHex.darkSecondary, PaletteHex.darkBackground), 4.5)
        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(PaletteHex.sepiaSecondary, PaletteHex.sepiaBackground), 4.5)
        XCTAssertEqual(ShareCardTheme.dark.colorScheme, .dark)
        XCTAssertEqual(ShareCardTheme.sepia.colorScheme, .light)
    }

    func testShareImageOpensTheCardSheetForAPostAndAHighlight() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 20)])
        let post = try XCTUnwrap(app.feed.posts.first)
        app.actions(for: post).shareImage()
        XCTAssertEqual(app.shareCardRequest?.content, ShareCardContent(post))
        XCTAssertNil(app.shareRequest)

        let target = try paragraph(app, ids[0], 3)
        app.marks.addHighlight(bookID: ids[0], start: target.charStart, end: target.textEnd)
        let item = try XCTUnwrap(app.highlights().first)
        app.shareImage(item)
        XCTAssertEqual(app.shareCardRequest?.content.text, target.text)
        XCTAssertEqual(app.shareCardRequest?.content.title, "Alpha")
    }

    func testCopyHighlightPutsTheCitationOnThePasteboard() throws {
        let (app, ids) = try makeApp(books: [("Alpha", 20)])
        let target = try paragraph(app, ids[0], 2)
        app.marks.addHighlight(bookID: ids[0], start: target.charStart, end: target.textEnd)
        let item = try XCTUnwrap(app.highlights().first)
        app.copyHighlight(item)
        XCTAssertEqual(UIPasteboard.general.string, ShareFormatter.citation(text: item.text, title: "Alpha", author: "Tester", chapter: item.chapter, percent: item.percent))
    }
}
