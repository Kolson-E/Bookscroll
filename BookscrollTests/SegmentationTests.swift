import SwiftData
import XCTest
@testable import Bookscroll

final class ParagraphSegmentationTests: XCTestCase {
    private let chapterHTML = """
    <html><head><title>Ignored</title></head><body>
    <h1>Chapter One</h1>
    <p>It was a bright cold day in April, and the clocks were striking the hour across the quiet town square.</p>
    <p>\u{201C}Are you coming?\u{201D}</p>
    <p>\u{201C}Yes.\u{201D}</p>
    <p class="break">* * *</p>
    <p>&#160;</p>
    <div class="poem"><p>Roses are red,<br/>violets are blue,<br/>these lines are kept<br/>as lines for you.</p></div>
    <h2>Interlude</h2>
    <p>After the heading the label changes for every paragraph that follows it, until the next heading appears in the text.</p>
    <p>One more paragraph with enough words to keep the document well above the forty word threshold for spine items.</p>
    </body></html>
    """

    private func paragraphs() -> [ParsedParagraph] {
        var label = ""
        return EPUBBookParser.paragraphsForDocument(
            blocks: HTMLTextExtractor.blocks(from: chapterHTML),
            navigationLabel: "Nav Label",
            carriedLabel: &label
        )
    }

    func testOneSegmentPerParagraph() {
        let segmented = Segmenter.segment(paragraphs())
        XCTAssertEqual(segmented.paragraphs.map(\.text), [
            "It was a bright cold day in April, and the clocks were striking the hour across the quiet town square.",
            "\u{201C}Are you coming?\u{201D}",
            "\u{201C}Yes.\u{201D}",
            "Roses are red,\nviolets are blue,\nthese lines are kept\nas lines for you.",
            "After the heading the label changes for every paragraph that follows it, until the next heading appears in the text.",
            "One more paragraph with enough words to keep the document well above the forty word threshold for spine items.",
        ])
    }

    func testNoMergesOrSplits() {
        let input = Fixtures.paragraphs(count: 60)
        let segmented = Segmenter.segment(input)
        XCTAssertEqual(segmented.paragraphs.count, input.count)
        XCTAssertEqual(segmented.paragraphs.map(\.text), input.map(\.text))
    }

    func testSceneBreaksDropped() {
        let texts = Segmenter.segment(paragraphs()).paragraphs.map(\.text)
        XCTAssertFalse(texts.contains("* * *"))
        XCTAssertTrue(texts.allSatisfy(TextUtils.hasLetterOrDigit))
        let direct = Segmenter.segment([
            ParsedParagraph(text: "Before.", chapter: ""),
            ParsedParagraph(text: "\u{2042}", chapter: ""),
            ParsedParagraph(text: "  ---  ", chapter: ""),
            ParsedParagraph(text: "After.", chapter: ""),
        ])
        XCTAssertEqual(direct.paragraphs.map(\.text), ["Before.", "After."])
    }

    func testHeadingsBecomeLabels() {
        let result = paragraphs()
        XCTAssertFalse(result.contains { $0.text == "Chapter One" || $0.text == "Interlude" }, "Headings are not posts")
        XCTAssertEqual(result.map(\.chapter), [
            "Chapter One", "Chapter One", "Chapter One", "Chapter One", "Interlude", "Interlude",
        ])
    }

    func testBreakLinesKept() {
        let poem = Segmenter.segment(paragraphs()).paragraphs[3]
        XCTAssertEqual(poem.text.components(separatedBy: "\n").count, 4)
    }

    func testNavigationLabelUsedWithoutHeading() {
        var label = "Old"
        let html = "<body>" + String(repeating: "<p>Plain words in a document that has no heading at all here.</p>", count: 5) + "</body>"
        let result = EPUBBookParser.paragraphsForDocument(
            blocks: HTMLTextExtractor.blocks(from: html),
            navigationLabel: "From Navigation",
            carriedLabel: &label
        )
        XCTAssertEqual(Set(result.map(\.chapter)), ["From Navigation"])
    }

    func testShortSpineItemSkipped() {
        var label = ""
        let result = EPUBBookParser.paragraphsForDocument(
            blocks: HTMLTextExtractor.blocks(from: "<h1>Contents</h1><p>Chapter One</p><p>Chapter Two</p>"),
            navigationLabel: nil,
            carriedLabel: &label
        )
        XCTAssertTrue(result.isEmpty)
    }
}

final class PassageChunkerTests: XCTestCase {
    func testMaximumWordLimitHolds() {
        var units: [PassageChunker.Unit] = []
        var state = 7
        for i in 0..<500 {
            state = (state &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
            units.append(PassageChunker.Unit(words: 1 + state % 60, endsParagraph: i % 4 == 3))
        }
        let groups = PassageChunker.chunk(units)
        for group in groups {
            let words = units[group].reduce(0) { $0 + $1.words }
            XCTAssertTrue(words <= PassageChunker.maximumWords || group.count == 1, "Passage of \(words) words from \(group.count) sentences")
        }
    }

    func testSingleLongSentenceMayExceedLimit() {
        let units = [
            PassageChunker.Unit(words: 20, endsParagraph: false),
            PassageChunker.Unit(words: 200, endsParagraph: false),
            PassageChunker.Unit(words: 20, endsParagraph: true),
        ]
        XCTAssertEqual(PassageChunker.chunk(units), [0..<1, 1..<2, 2..<3])
    }

    func testClosesNearTarget() {
        let units = Array(repeating: PassageChunker.Unit(words: 10, endsParagraph: false), count: 40)
        let groups = PassageChunker.chunk(units)
        for group in groups.dropLast() {
            XCTAssertEqual(units[group].reduce(0) { $0 + $1.words }, 80)
        }
    }

    func testWordTotalsPreserved() {
        let input = Fixtures.paragraphs(count: 120)
        let segmented = Segmenter.segment(input)
        let inputWords = input.reduce(0) { $0 + TextUtils.wordCount($1.text) }
        let passageWords = segmented.passages.reduce(0) { $0 + TextUtils.wordCount($1.text) }
        XCTAssertEqual(passageWords, inputWords)
        XCTAssertEqual(TextUtils.wordCount(segmented.normalizedText), inputWords)
    }

    func testPassagesRespectLimitOnRealText() {
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 120))
        let splitter = SentenceSplitter()
        for passage in segmented.passages {
            let words = TextUtils.wordCount(passage.text)
            if words > PassageChunker.maximumWords {
                XCTAssertEqual(splitter.sentenceStarts(in: passage.text).count, 1, "Only a single sentence may exceed the limit")
            }
        }
    }

    func testShortParagraphsMerge() {
        let short = (0..<12).map { _ in ParsedParagraph(text: "This short paragraph has exactly ten words in it now.", chapter: "One") }
        XCTAssertEqual(TextUtils.wordCount(short[0].text), 10)
        let segmented = Segmenter.segment(short)
        XCTAssertEqual(segmented.passages.count, 3)
        for passage in segmented.passages {
            XCTAssertEqual(TextUtils.wordCount(passage.text), 40)
            XCTAssertEqual(passage.text.components(separatedBy: "\n\n").count, 4, "Four paragraphs merged into one passage")
        }
    }

    func testClosesAtParagraphEndAfterForty() {
        let units = [
            PassageChunker.Unit(words: 25, endsParagraph: false),
            PassageChunker.Unit(words: 20, endsParagraph: true),
            PassageChunker.Unit(words: 10, endsParagraph: true),
        ]
        XCTAssertEqual(PassageChunker.chunk(units), [0..<2, 2..<3])
    }

    func testPassagesNeverSpanChapters() {
        let paragraphs = [
            ParsedParagraph(text: "One two three four five.", chapter: "A"),
            ParsedParagraph(text: "Six seven eight nine ten.", chapter: "B"),
        ]
        let segmented = Segmenter.segment(paragraphs)
        XCTAssertEqual(segmented.passages.map(\.chapter), ["A", "B"])
    }

    func testEmptyInputGivesNoPassages() {
        XCTAssertTrue(PassageChunker.chunk([]).isEmpty)
        let segmented = Segmenter.segment([])
        XCTAssertTrue(segmented.passages.isEmpty)
        XCTAssertTrue(segmented.paragraphs.isEmpty)
        XCTAssertEqual(segmented.totalCharacters, 0)
        XCTAssertTrue(Segmenter.segment([ParsedParagraph(text: " * * * ", chapter: "")]).passages.isEmpty)
    }
}

final class TilingTests: XCTestCase {
    func testParagraphSegmentsTileText() {
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 80))
        XCTAssertEqual(segmented.totalCharacters, (segmented.normalizedText as NSString).length)
        assertTiles(segmented.paragraphs, text: segmented.normalizedText)
    }

    func testPassageSegmentsTileText() {
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 80))
        assertTiles(segmented.passages, text: segmented.normalizedText)
    }

    func testTilingWithUnicodeAndLineBreaks() {
        let paragraphs = [
            ParsedParagraph(text: "  Caf\u{00E9} \u{1F600} na\u{00EF}ve r\u{00E9}sum\u{00E9}.  ", chapter: "I"),
            ParsedParagraph(text: "Line one\n\n\nline two\r\nline three", chapter: "I"),
            ParsedParagraph(text: "\u{201C}Quote.\u{201D} Another sentence here! And a third?", chapter: "II"),
        ]
        let segmented = Segmenter.segment(paragraphs)
        XCTAssertEqual(segmented.paragraphs[1].text, "Line one\nline two\nline three")
        assertTiles(segmented.paragraphs, text: segmented.normalizedText)
        assertTiles(segmented.passages, text: segmented.normalizedText)
    }
}

final class StyleSwitchTests: XCTestCase {
    func testOffsetMapsToContainingSegmentInBothStyles() {
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 70))
        for offset in stride(from: 0, to: segmented.totalCharacters, by: 13) {
            let p = try! XCTUnwrap(SegmentLocator.index(containing: offset, in: segmented.paragraphs))
            let q = try! XCTUnwrap(SegmentLocator.index(containing: offset, in: segmented.passages))
            let paragraph = segmented.paragraphs[p]
            let passage = segmented.passages[q]
            XCTAssertTrue(paragraph.charStart <= offset && offset < paragraph.charEnd, "Paragraph \(p) does not contain \(offset)")
            XCTAssertTrue(passage.charStart <= offset && offset < passage.charEnd, "Passage \(q) does not contain \(offset)")
        }
    }

    func testSwitchingStyleKeepsPlace() {
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 70))
        let source = InMemorySegmentSource()
        let id = UUID()
        source.add(bookID: id, segmented: segmented)

        // Read in Paragraphs style, then switch to Passages, then back.
        let start = segmented.paragraphs[23].charStart + 5
        var book = Fixtures.feedBook(id: id, ordinal: 1, title: "B", segmented: segmented, position: start)
        let paragraphEngine = FeedEngine(source: source, books: [book], style: .paragraph, mode: .single(id), seed: 1)
        paragraphEngine.loadMore()
        XCTAssertTrue(paragraphEngine.posts[0].segment.contains(offset: start))
        let shown = paragraphEngine.posts[4]
        let updates = paragraphEngine.markShown(through: shown.id)
        let offset = try! XCTUnwrap(updates[id])
        XCTAssertEqual(offset, shown.segment.charStart)

        book.positionOffset = offset
        let passageEngine = FeedEngine(source: source, books: [book], style: .passage, mode: .single(id), seed: 1)
        passageEngine.loadMore()
        let firstPassage = passageEngine.posts[0].segment
        XCTAssertEqual(firstPassage.style, .passage)
        XCTAssertTrue(firstPassage.contains(offset: offset), "Passage \(firstPassage.charStart)..<\(firstPassage.charEnd) does not contain \(offset)")

        // Back to paragraphs from a passage position.
        let passageShown = passageEngine.posts[3]
        passageEngine.markShown(through: passageShown.id)
        book.positionOffset = passageShown.segment.charStart
        let backEngine = FeedEngine(source: source, books: [book], style: .paragraph, mode: .single(id), seed: 1)
        backEngine.loadMore()
        XCTAssertTrue(backEngine.posts[0].segment.contains(offset: passageShown.segment.charStart))
    }
}

final class MarkTests: XCTestCase {
    func testBookmarkInOneStyleShowsOnOverlappingPostsInOtherStyle() {
        let segmented = Segmenter.segment(Fixtures.paragraphs(count: 40))
        let id = UUID()
        let bookmarked = segmented.paragraphs[12]
        let index = MarkIndex([MarkRecord(bookID: id, kind: .bookmark, charStart: bookmarked.charStart, charEnd: bookmarked.charEnd)])

        var bookmarkedPassages = 0
        for passage in segmented.passages {
            let overlaps = passage.charStart < bookmarked.charEnd && bookmarked.charStart < passage.charEnd
            XCTAssertEqual(index.isMarked(.bookmark, bookID: id, start: passage.charStart, end: passage.charEnd), overlaps)
            XCTAssertFalse(index.isMarked(.highlight, bookID: id, start: passage.charStart, end: passage.charEnd), "A bookmark is not a highlight")
            if overlaps { bookmarkedPassages += 1 }
        }
        XCTAssertGreaterThan(bookmarkedPassages, 0)
        XCTAssertFalse(index.isMarked(.bookmark, bookID: UUID(), start: bookmarked.charStart, end: bookmarked.charEnd))

        // And the other way: a passage bookmark marks every paragraph it touches.
        let passage = segmented.passages[5]
        let passageIndex = MarkIndex([MarkRecord(bookID: id, kind: .bookmark, charStart: passage.charStart, charEnd: passage.charEnd)])
        let marked = segmented.paragraphs.filter {
            passageIndex.isMarked(.bookmark, bookID: id, start: $0.charStart, end: $0.charEnd)
        }
        XCTAssertFalse(marked.isEmpty)
        for paragraph in segmented.paragraphs {
            let overlaps = paragraph.charStart < passage.charEnd && passage.charStart < paragraph.charEnd
            XCTAssertEqual(marked.contains(paragraph), overlaps)
        }
    }

    func testMarksPersistAndMatchAcrossStyles() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let parsed = ParsedBook(
            title: "Marked",
            author: "Tester",
            format: .epub,
            paragraphs: Fixtures.paragraphs(count: 30),
            passagesOnly: false,
            note: nil
        )
        let segmented = Segmenter.segment(parsed.paragraphs)
        let bookID = try BookWriter.write(parsed: parsed, segmented: segmented, into: context)
        let store = LibraryStore(context: context)
        let book = try XCTUnwrap(store.feedBook(id: bookID))

        let paragraph = try XCTUnwrap(store.segments(book: book, style: .paragraph, from: 7, limit: 1).first)
        XCTAssertNotNil(store.addMark(kind: .bookmark, bookID: bookID, charStart: paragraph.charStart, charEnd: paragraph.charEnd))

        let index = MarkIndex(store.allMarks())
        let overlapping = store.segmentsOverlapping(start: paragraph.charStart, end: paragraph.charEnd, book: book, style: .passage)
        XCTAssertFalse(overlapping.isEmpty)
        for passage in store.segments(book: book, style: .passage, from: 0, limit: 1000) {
            let expected = overlapping.contains(passage)
            XCTAssertEqual(index.isMarked(.bookmark, bookID: bookID, start: passage.charStart, end: passage.charEnd), expected)
        }

        store.deleteMarks(ids: store.allMarks().map(\.id))
        XCTAssertTrue(store.allMarks().isEmpty)
    }
}
