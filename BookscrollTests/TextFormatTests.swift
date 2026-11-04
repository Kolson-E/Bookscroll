import SwiftData
import UIKit
import XCTest
@testable import Bookscroll

/// Plain text, Markdown, HTML, RTF and pasted text.
final class TextFormatTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ text: String, name: String, encoding: String.Encoding = .utf8) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try XCTUnwrap(text.data(using: encoding)).write(to: url)
        return url
    }

    // MARK: Plain text

    func testHardWrappedTextJoinsLinesAndFindsChapters() throws {
        let text = """
        CHAPTER I

        The river ran fast under the old
        stone bridge, and nobody in the town
        could remember when it was built.

        Children threw sticks from one side
        and raced across to watch them.

        Chapter 2: The Flood

        In spring the water rose.
        """
        let url = try write(text, name: "River.txt")
        let parsed = try BookImporter.parse(url: url) { _ in }
        XCTAssertEqual(parsed.format, .text)
        XCTAssertEqual(parsed.title, "River")
        XCTAssertEqual(parsed.author, "Unknown author")
        XCTAssertEqual(parsed.paragraphs, [
            ParsedParagraph(text: "The river ran fast under the old stone bridge, and nobody in the town could remember when it was built.", chapter: "CHAPTER I"),
            ParsedParagraph(text: "Children threw sticks from one side and raced across to watch them.", chapter: "CHAPTER I"),
            ParsedParagraph(text: "In spring the water rose.", chapter: "Chapter 2: The Flood"),
        ])
    }

    func testTextWithoutBlankLinesHasOneParagraphPerLine() {
        let parsed = TextBookParser.parsePlain("First line here.\r\nSecond line here.\rThird.", title: nil, author: nil, fallbackTitle: "T", format: .text)
        XCTAssertEqual(parsed.paragraphs.map(\.text), ["First line here.", "Second line here.", "Third."])
    }

    func testChapterHeadingRules() {
        for heading in ["Chapter 1", "CHAPTER XII", "Part Two", "Prologue", "Epilogue.", "Prologue: The Arrival", "CHAPTER THE FIRST", "I", "IV", "XII.", "12", "Kapitel 3", "Book I: Arrival"] {
            XCTAssertTrue(TextBookParser.isChapterHeading(heading), heading)
        }
        for line in ["The river ran fast.", "Chapters of my life were long and short and many, as you know,", "Part of me knew.", "Act now.", "Book of hours", "CIVIL", "DID", "1984 was a year", "A", "Partly cloudy all day today and tomorrow in the north and the west, said the radio."] {
            XCTAssertFalse(TextBookParser.isChapterHeading(line), line)
        }
    }

    func testGutenbergFrameIsRemovedAndReadsTitleAndAuthor() throws {
        let text = """
        The Project Gutenberg eBook of Harbour Tales

        Title: Harbour Tales

        Author: Ada Example

        *** START OF THE PROJECT GUTENBERG EBOOK HARBOUR TALES ***

        The harbour was full of small boats.

        The gulls argued over every crate.

        Mara watched them from the wall.

        *** END OF THE PROJECT GUTENBERG EBOOK HARBOUR TALES ***

        Licence text that is not part of the book.
        """
        let parsed = try BookImporter.parse(url: try write(text, name: "pg123.txt")) { _ in }
        XCTAssertEqual(parsed.title, "Harbour Tales")
        XCTAssertEqual(parsed.author, "Ada Example")
        XCTAssertEqual(parsed.paragraphs.map(\.text), [
            "The harbour was full of small boats.",
            "The gulls argued over every crate.",
            "Mara watched them from the wall.",
        ])
    }

    func testEncodings() throws {
        let text = "Caf\u{00E9} au lait, s\u{2019}il vous pla\u{00EE}t.\n\nDeux.\n\nTrois."
        for (encoding, name) in [(String.Encoding.utf8, "utf8.txt"), (.utf16, "utf16.txt"), (.windowsCP1252, "latin.txt")] {
            let parsed = try BookImporter.parse(url: try write(text, name: name, encoding: encoding)) { _ in }
            XCTAssertEqual(parsed.paragraphs.first?.text, "Caf\u{00E9} au lait, s\u{2019}il vous pla\u{00EE}t.", name)
        }
        var bom = Data([0xEF, 0xBB, 0xBF])
        bom.append(Data("Hello.\n\nTwo.\n\nThree.".utf8))
        XCTAssertEqual(TextBookParser.decode(bom)?.hasPrefix("Hello."), true, "The byte order mark is dropped")
        XCTAssertNil(TextBookParser.decode(Data([0x41, 0x00, 0x42])), "Binary data")
    }

    // MARK: Markdown

    func testMarkdown() throws {
        let markdown = """
        ---
        title: "Field Notes"
        author: Ben Sample
        ---

        Intro paragraph with **bold**, *emphasis*, `code` and a [link](https://example.com).

        ## Day One

        The tide turned at noon.
        It was quiet.

        - First item
        - Second item

        > A quoted line.

        ![A map](map.png)

        ---

        ### Day Two

        1. Numbered item

        ```
        let x = 1
        ```
        """
        let parsed = try BookImporter.parse(url: try write(markdown, name: "notes.md")) { _ in }
        XCTAssertEqual(parsed.format, .markdown)
        XCTAssertEqual(parsed.title, "Field Notes")
        XCTAssertEqual(parsed.author, "Ben Sample")
        XCTAssertEqual(parsed.paragraphs, [
            ParsedParagraph(text: "Intro paragraph with bold, emphasis, code and a link.", chapter: ""),
            ParsedParagraph(text: "The tide turned at noon. It was quiet.", chapter: "Day One"),
            ParsedParagraph(text: "First item", chapter: "Day One"),
            ParsedParagraph(text: "Second item", chapter: "Day One"),
            ParsedParagraph(text: "A quoted line.", chapter: "Day One"),
            ParsedParagraph(text: "Numbered item", chapter: "Day Two"),
            ParsedParagraph(text: "let x = 1", chapter: "Day Two"),
        ])
    }

    func testMarkdownTitleFromFirstHeading() {
        let parsed = TextBookParser.parseMarkdown("# My Essay\n\nFirst paragraph.\n\n# Part One\n\nSecond paragraph.", fallbackTitle: "file")
        XCTAssertEqual(parsed.title, "My Essay")
        XCTAssertEqual(parsed.paragraphs.map(\.chapter), ["", "Part One"])
        XCTAssertEqual(TextBookParser.parseMarkdown("Text first.\n\n# Heading\n\nMore.", fallbackTitle: "file").title, "file")
    }

    func testInlineMarkup() {
        XCTAssertEqual(TextBookParser.inlineText("snake_case_name stays"), "snake_case_name stays")
        XCTAssertEqual(TextBookParser.inlineText("2 * 3 * 4"), "2 * 3 * 4")
        XCTAssertEqual(TextBookParser.inlineText("__strong__ and _em_ and ~~gone~~"), "strong and em and gone")
        XCTAssertEqual(TextBookParser.inlineText(#"Escaped \*stars\* &amp; <span>tags</span>"#), "Escaped *stars* & tags")
    }

    // MARK: HTML and RTF

    func testHTML() throws {
        let html = """
        <!DOCTYPE html><html><head><title>An &amp; Article</title>
        <meta name="author" content="Ada Example"><style>p{}</style></head>
        <body><h1>Opening</h1><p>First <em>paragraph</em>.</p><p>Second paragraph.</p>
        <h2>Later</h2><div>Third block.</div><script>var x = "<p>no</p>";</script></body></html>
        """
        let parsed = try BookImporter.parse(url: try write(html, name: "page.html")) { _ in }
        XCTAssertEqual(parsed.format, .html)
        XCTAssertEqual(parsed.title, "An & Article")
        XCTAssertEqual(parsed.author, "Ada Example")
        XCTAssertEqual(parsed.paragraphs, [
            ParsedParagraph(text: "First paragraph.", chapter: "Opening"),
            ParsedParagraph(text: "Second paragraph.", chapter: "Opening"),
            ParsedParagraph(text: "Third block.", chapter: "Later"),
        ])
    }

    func testRTFIsKnownByItsFirstBytes() throws {
        let attributed = NSAttributedString(string: "Chapter 1\nThe river ran fast.\nIt was cold.\n")
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let url = folder.appendingPathComponent("story.doc") // a wrong extension
        try data.write(to: url)
        XCTAssertEqual(try BookImporter.detectFormat(url), .rtf)
        let parsed = try BookImporter.parse(url: url) { _ in }
        XCTAssertEqual(parsed.format, .rtf)
        XCTAssertEqual(parsed.title, "story")
        XCTAssertEqual(parsed.paragraphs, [
            ParsedParagraph(text: "The river ran fast.", chapter: "Chapter 1"),
            ParsedParagraph(text: "It was cold.", chapter: "Chapter 1"),
        ])
    }

    func testFormatsFromExtensions() {
        XCTAssertEqual(BookFormat.fromExtension("TXT"), .text)
        XCTAssertEqual(BookFormat.fromExtension("markdown"), .markdown)
        XCTAssertEqual(BookFormat.fromExtension("htm"), .html)
        XCTAssertEqual(BookFormat.fromExtension("rtf"), .rtf)
        XCTAssertNil(BookFormat.fromExtension("docx"))
        XCTAssertEqual(BookFormat.allCases.map(\.label), ["EPUB", "PDF", "TXT", "MD", "HTML", "RTF"])
    }

    // MARK: Import and paste

    func testTextFileImportsIntoTheLibrary() throws {
        let url = try write("One paragraph here.\n\nAnother one here.\n\nAnd a third.", name: "Short.txt")
        let container = try Fixtures.makeContainer()
        let id = try BookImporter.importBook(at: url, into: container)
        let book = try XCTUnwrap(LibraryStore(context: ModelContext(container)).book(id: id))
        XCTAssertEqual(book.format, .text)
        XCTAssertEqual(book.title, "Short")
        XCTAssertEqual(book.paragraphSegmentCount, 3)
        XCTAssertEqual(book.sourceFileName, "Short.txt")
    }

    func testEmptyTextFileHasNoText() throws {
        let url = try write("\n\n   \n", name: "Empty.txt")
        XCTAssertThrowsError(try BookImporter.importBook(at: url, into: try Fixtures.makeContainer())) { error in
            XCTAssertEqual(error as? BookImportError, .noText)
        }
    }

    func testPastedText() throws {
        let container = try Fixtures.makeContainer()
        let id = try BookImporter.importPasted(
            text: "Part One\n\nThe first pasted paragraph.\n\nThe second one.",
            title: "  My  Notes ",
            author: "",
            into: container
        )
        let store = LibraryStore(context: ModelContext(container))
        let book = try XCTUnwrap(store.book(id: id))
        XCTAssertEqual(book.title, "My Notes")
        XCTAssertEqual(book.author, "Unknown author")
        XCTAssertEqual(book.format, .text)
        XCTAssertNil(book.sourceFileName)
        XCTAssertEqual(store.chapters(bookID: id).map(\.title), ["Part One"])

        let untitled = TextBookParser.parsePasted("Some text.", title: " ", author: "Me")
        XCTAssertEqual(untitled.title, "Pasted text")
        XCTAssertEqual(untitled.author, "Me")
    }

    @MainActor
    func testPasteJobRunsInTheQueue() async throws {
        let container = try Fixtures.makeContainer()
        let manager = ImportManager(container: container)
        let finished = expectation(description: "queue finished")
        manager.onQueueFinished = { finished.fulfill() }
        manager.enqueuePasted(text: "   ", title: "Blank", author: "")
        manager.enqueuePasted(text: "A real paragraph.", title: "Real", author: "")
        XCTAssertEqual(manager.jobs.map(\.fileName), ["Blank", "Real"])
        await fulfillment(of: [finished], timeout: 30)
        XCTAssertEqual(manager.jobs.count, 1, "The good one finished and left the list")
        XCTAssertEqual(manager.jobs.first?.status, .failed(BookImportError.noText.errorDescription!))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Book>()).map(\.title), ["Real"])
    }
}
