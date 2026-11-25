import SwiftData
import UIKit
import XCTest
@testable import Bookscroll

/// Pictures in books: found in EPUBs, placed after the paragraph they follow, kept as files,
/// and shown under the post that ends at them.
final class BookImageTests: XCTestCase {
    private var folder: URL!
    private var savedDirectory: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
        savedDirectory = BookImageStore.directory
        BookImageStore.directory = folder.appendingPathComponent("BookImages", isDirectory: true)
    }

    override func tearDownWithError() throws {
        BookImageStore.directory = savedDirectory
        try? FileManager.default.removeItem(at: folder)
    }

    /// A picture of the given size, as PNG (with transparency) or JPEG.
    static func picture(width: Int, height: Int, transparent: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !transparent
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let draw: (UIGraphicsImageRendererContext) -> Void = { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        }
        return transparent ? renderer.pngData(actions: draw) : renderer.jpegData(withCompressionQuality: 0.9, actions: draw)
    }

    // MARK: HTML

    func testImagesComeAfterTheTextOfTheirBlock() {
        let html = """
        <html><body>
        <p>Before the <img src="../Images/a.png" alt="A &amp; B"/> picture.</p>
        <div><img src='b.jpg'/></div>
        <svg xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="c.jpeg"/></svg>
        <p>After. <img src="data:image/png;base64,AAAA"/></p>
        </body></html>
        """
        XCTAssertEqual(HTMLTextExtractor.blocks(from: html, images: true), [
            HTMLBlock(text: "Before the picture.", headingLevel: nil),
            HTMLBlock(text: "", headingLevel: nil, image: HTMLImage(source: "../Images/a.png", alt: "A & B")),
            HTMLBlock(text: "", headingLevel: nil, image: HTMLImage(source: "b.jpg", alt: "")),
            HTMLBlock(text: "", headingLevel: nil, image: HTMLImage(source: "c.jpeg", alt: "")),
            HTMLBlock(text: "After.", headingLevel: nil),
        ], "An image inside a paragraph follows its text; inline data images are left out")
        XCTAssertEqual(HTMLTextExtractor.blocks(from: html).map(\.text), ["Before the picture.", "After."], "Without `images`, text only")
    }

    // MARK: Segmenter

    func testAPictureIsPlacedAtTheEndOfTheParagraphBeforeIt() {
        let paragraphs = [
            ParsedParagraph(text: "First paragraph.", chapter: "One", images: []),
            ParsedParagraph(text: "Second paragraph.", chapter: "One", images: [0]),
            ParsedParagraph(text: "* * *", chapter: "One", images: [1]),
            ParsedParagraph(text: "Third paragraph.", chapter: "One", images: []),
        ]
        let book = Segmenter.segment(paragraphs)
        XCTAssertEqual(book.paragraphs.count, 3, "The scene break is dropped")
        let second = book.paragraphs[1]
        let end = second.charStart + second.text.utf16.count
        XCTAssertEqual(book.imageAnchors, [ImageAnchor(offset: end, image: 0), ImageAnchor(offset: end, image: 1)],
                       "A dropped paragraph's picture goes to the paragraph before it")
        for anchor in book.imageAnchors {
            let holders = book.paragraphs.filter { $0.charStart < anchor.offset && anchor.offset <= $0.charEnd }
            XCTAssertEqual(holders.map(\.index), [1], "Exactly one post holds the picture")
        }
        assertTiles(book.paragraphs, text: book.normalizedText)
        assertTiles(book.passages, text: book.normalizedText)
    }

    func testPicturesBeforeAnyTextFollowTheFirstParagraph() {
        let book = Segmenter.segment([
            ParsedParagraph(text: "", chapter: "", images: [0]),
            ParsedParagraph(text: "Opening words.", chapter: "", images: [1]),
        ])
        let end = "Opening words.".utf16.count
        XCTAssertEqual(book.imageAnchors, [ImageAnchor(offset: end, image: 0), ImageAnchor(offset: end, image: 1)])
    }

    func testAPassageEndsAtAPicture() {
        // Short paragraphs would join one passage; the picture after the second one ends it there.
        let words = "one two three four five six seven eight nine ten."
        let paragraphs = (0..<6).map { ParsedParagraph(text: "Line \($0) \(words)", chapter: "A", images: $0 == 1 ? [0] : []) }
        let withPicture = Segmenter.segment(paragraphs)
        let without = Segmenter.segment(paragraphs.map { ParsedParagraph(text: $0.text, chapter: $0.chapter) })
        XCTAssertEqual(without.passages.count, 2, "Without the picture: two passages")
        let anchor = withPicture.imageAnchors[0].offset
        let holder = withPicture.passages.first { $0.charStart < anchor && anchor <= $0.charEnd }
        XCTAssertEqual(holder?.charStart, 0)
        XCTAssertEqual(holder.map { $0.charStart + $0.text.utf16.count }, anchor, "The passage's text ends at the picture")
        XCTAssertGreaterThan(withPicture.passages.count, 1, "The next passage continues the book")
        assertTiles(withPicture.passages, text: withPicture.normalizedText)
    }

    func testOnlyTheLastPartOfASplitPostShowsThePicture() {
        let text = (1...12).map { "Sentence number \($0) has several words in it." }.joined(separator: " ")
        let book = Segmenter.segment([ParsedParagraph(text: text, chapter: "", images: [0])])
        let segment = SegmentRecord(bookID: UUID(), draft: book.paragraphs[0])
        let pieces = PostPiece.pieces(of: segment, limit: 20, splitter: SentenceSplitter())
        XCTAssertGreaterThan(pieces.count, 2)
        let entry = BookImageEntry(offset: book.imageAnchors[0].offset, file: "0.jpg", width: 10, height: 10, alt: "")
        XCTAssertEqual(pieces.map { entry.belongs(toStart: $0.segment.charStart, end: $0.segment.charEnd) },
                       Array(repeating: false, count: pieces.count - 1) + [true])
    }

    // MARK: Files

    func testPicturesAreCheckedAndKeptOrScaledDown() throws {
        let staging = BookImageStore.makeStagingFolder()
        defer { try? FileManager.default.removeItem(at: staging) }

        let small = try XCTUnwrap(BookImageStore.prepare(Self.picture(width: 600, height: 400), name: "a", in: staging))
        XCTAssertEqual(small.file.pathExtension, "jpeg", "A common format of normal size keeps its bytes")
        XCTAssertEqual([small.width, small.height], [600, 400])

        let large = try XCTUnwrap(BookImageStore.prepare(Self.picture(width: 3000, height: 1000), name: "b", in: staging))
        XCTAssertEqual(large.width, 2048, "A large picture is scaled down")
        XCTAssertEqual(Double(large.height), 683, accuracy: 1)
        XCTAssertEqual(large.file.pathExtension, "jpg")

        let clear = try XCTUnwrap(BookImageStore.prepare(Self.picture(width: 2600, height: 600, transparent: true), name: "c", in: staging))
        XCTAssertEqual(clear.file.pathExtension, "png", "Transparency stays (PNG)")

        XCTAssertNil(BookImageStore.prepare(Self.picture(width: 300, height: 20), name: "d", in: staging), "A thin rule is decoration")
        XCTAssertNil(BookImageStore.prepare(Data("<svg/>".utf8), name: "e", in: staging), "Not an image ImageIO shows")
    }

    @MainActor
    func testTheCacheFindsThePicturesOfARange() async throws {
        let staging = BookImageStore.makeStagingFolder()
        let file = try XCTUnwrap(BookImageStore.prepare(Self.picture(width: 100, height: 100), name: "0", in: staging))
        let image = ParsedImage(file: file.file, width: 100, height: 100, alt: "")
        let bookID = UUID()
        let anchors = [ImageAnchor(offset: 50, image: 0), ImageAnchor(offset: 10, image: 0), ImageAnchor(offset: 50, image: 0)]
        let saved = BookImageStore.save([image], anchors: anchors, bookID: bookID)
        XCTAssertEqual(saved.map(\.offset), [10, 50, 50], "In text order")

        let cache = BookImageCache()
        cache.root = BookImageStore.directory
        XCTAssertEqual(cache.images(bookID: bookID, start: 0, end: 9), [])
        XCTAssertEqual(cache.images(bookID: bookID, start: 0, end: 10).map(\.offset), [10])
        XCTAssertEqual(cache.images(bookID: bookID, start: 10, end: 60).map(\.offset), [50, 50], "The start is outside the range")
        XCTAssertEqual(cache.images(bookID: UUID(), start: 0, end: 100), [], "A book without pictures")
        let image40 = await cache.image(saved[0], bookID: bookID, pixels: 40)
        let decoded = try XCTUnwrap(image40)
        XCTAssertEqual(max(decoded.size.width, decoded.size.height), 40, "Decoded at the asked size")
        XCTAssertGreaterThan(BookImageStore.size(bookID: bookID), 0)
        BookImageStore.remove(bookID: bookID)
        XCTAssertEqual(BookImageStore.entries(bookID: bookID), [])
    }

    // MARK: EPUB

    private static func page(_ body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>x</title></head><body>\(body)</body></html>"
    }

    private static let filler = "The boats came in slowly with the evening tide while the town lit its lamps one by one along the harbour wall and the gulls settled on the roofs."

    /// An EPUB with a cover page, a chapter with pictures (one real, one tiny, one missing, an
    /// ornament used three times), a page with only a picture, and a second chapter.
    private func writePictureBook(to url: URL) throws {
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">x</dc:identifier><dc:title>Pictures</dc:title><dc:creator>Ann Artist</dc:creator></metadata>
          <manifest>
            <item id="cover" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="Text/one.xhtml" media-type="application/xhtml+xml"/>
            <item id="plate" href="Text/plate.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="Text/two.xhtml" media-type="application/xhtml+xml"/>
            <item id="coverimg" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
          </manifest>
          <spine><itemref idref="cover"/><itemref idref="c1"/><itemref idref="plate"/><itemref idref="c2"/></spine>
        </package>
        """
        let one = Self.page("""
        <h1>One</h1>
        <p>\(Self.filler)</p>
        <p>\(Self.filler) <img src="../Images/boat.jpg" alt="A boat"/></p>
        <p class="break"><img src="../Images/rule.png"/></p>
        <p>\(Self.filler)</p>
        <div><img src="../Images/dot.png"/><img src="../Images/missing.png"/></div>
        <p>\(Self.filler)</p>
        <p><img src="../Images/rule.png"/></p>
        <p>\(Self.filler)</p>
        <p><img src="../Images/rule.png"/></p>
        """)
        let plate = Self.page("<div><img src=\"../Images/plate.png\" alt=\"The harbour at night\"/></div>")
        let two = Self.page("<h1>Two</h1><p>\(Self.filler)</p><p>\(Self.filler)</p>")
        let cover = Self.page("<div><img src=\"../Images/cover.jpg\"/></div>")
        try ZipWriter.write(entries: [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(EPUBFixture.container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/Text/cover.xhtml", Data(cover.utf8)),
            ("OEBPS/Text/one.xhtml", Data(one.utf8)),
            ("OEBPS/Text/plate.xhtml", Data(plate.utf8)),
            ("OEBPS/Text/two.xhtml", Data(two.utf8)),
            ("OEBPS/Images/cover.jpg", Self.picture(width: 400, height: 600)),
            ("OEBPS/Images/boat.jpg", Self.picture(width: 800, height: 600)),
            ("OEBPS/Images/rule.png", Self.picture(width: 500, height: 200, transparent: true)),
            ("OEBPS/Images/dot.png", Self.picture(width: 12, height: 12, transparent: true)),
            ("OEBPS/Images/plate.png", Self.picture(width: 600, height: 900, transparent: true)),
        ], to: url)
    }

    func testAnEPUBsPicturesFollowTheirParagraphsAndAreStored() throws {
        let url = folder.appendingPathComponent("pictures.epub")
        try writePictureBook(to: url)
        let parsed = try BookImporter.parse(url: url) { _ in }

        XCTAssertEqual(parsed.paragraphs.count, 7)
        XCTAssertEqual(parsed.images.map(\.alt), ["A boat", "The harbour at night"],
                       "The cover, the tiny dot, the missing file and the ornament used three times are left out")
        XCTAssertEqual(parsed.images.map { [$0.width, $0.height] }, [[800, 600], [600, 900]])
        XCTAssertEqual(parsed.paragraphs.map(\.images), [[], [0], [], [], [1], [], []],
                       "The boat follows its paragraph; the picture page follows the last paragraph before it")
        XCTAssertEqual(parsed.paragraphs[6].chapter, "Two")

        let container = try Fixtures.makeContainer()
        let staged = { try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path).filter { $0.hasPrefix("BookImages-") }.count }
        let stagedBefore = try staged()
        let bookID = try BookImporter.importBook(at: url, into: container)
        XCTAssertEqual(try staged(), stagedBefore, "The import's temporary folder is gone")
        let entries = BookImageStore.entries(bookID: bookID)
        XCTAssertEqual(entries.map(\.alt), ["A boat", "The harbour at night"])
        for entry in entries {
            XCTAssertNotNil(UIImage(contentsOfFile: BookImageStore.url(of: entry, bookID: bookID).path), "\(entry.file) is stored")
        }

        // Each picture is under exactly one post, in both styles, and it is that post's last thing.
        let store = LibraryStore(context: ModelContext(container))
        let book = FeedBook(try XCTUnwrap(store.book(id: bookID)))
        for style in [PostStyle.paragraph, .passage] {
            let segments = store.segments(book: book, style: style, from: 0, limit: 100)
            for entry in entries {
                let holders = segments.filter { entry.belongs(toStart: $0.charStart, end: $0.charEnd) }
                XCTAssertEqual(holders.count, 1, "\(style)")
                XCTAssertEqual(holders.first?.textEnd, entry.offset, "\(style): the post's text ends at the picture")
            }
        }
    }

    @MainActor
    func testDeletingABookRemovesItsPictures() async throws {
        let url = folder.appendingPathComponent("pictures.epub")
        try writePictureBook(to: url)
        let container = try Fixtures.makeContainer()
        let bookID = try BookImporter.importBook(at: url, into: container)
        let previousRoot = BookImageCache.shared.root
        BookImageCache.shared.root = BookImageStore.directory
        defer { BookImageCache.shared.root = previousRoot }
        XCTAssertEqual(BookImageCache.shared.entries(bookID: bookID).count, 2)

        let app = AppModel(container: container)
        await app.deleteBook(id: bookID)?.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: BookImageStore.folder(bookID: bookID).path))
        XCTAssertEqual(BookImageCache.shared.entries(bookID: bookID), [])
    }
}
