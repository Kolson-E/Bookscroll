import SwiftData
import XCTest
@testable import Bookscroll

/// Builds a small EPUB 3 file with a cover, a navigation document, a percent-encoded chapter
/// path, a chapter without headings and a stylesheet.
enum EPUBFixture {
    static let chapterOne = """
    <?xml version="1.0" encoding="utf-8"?>
    <!DOCTYPE html>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
    <head><title>Chapter One</title>
    <link rel="stylesheet" href="../Styles/book.css"/>
    <style>p { text-indent: 1em; }</style>
    <script>var hidden = "<p>do not show</p>";</script>
    </head>
    <body>
    <section epub:type="chapter">
    <h1>Chapter One</h1>
    <p>The harbour was full of small boats that morning, and the gulls &amp; the fishermen argued over every crate.</p>
    <p>&#8220;Is it always like this?&#8221; asked Mara.</p>
    <p>&#8220;Only on market days.&#8221;</p>
    <p class="scene">* * *</p>
    <p>The tide turned at noon&#8212;quietly, the way it always did&#8212;and the boats began to lean against their ropes.</p>
    <p class="verse">Salt on the wind,<br/>salt on the stone,<br/>salt in the bread<br/>we carry home.</p>
    </section>
    </body>
    </html>
    """

    static let chapterTwo = """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head><title>Part Two</title></head>
    <body>
    <div class="text">
    <div>Mara walked up the hill behind the harbour, past the chapel and the long white wall of the cemetery.</div>
    <div>From the top she could see the whole bay, the islands, and the grey line of the far coast.</div>
    <div>She stayed there until the light went, counting the boats as they came home one by one.</div>
    </div>
    </body>
    </html>
    """

    static let cover = """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head>
    <body><div><img src="../Images/cover.jpg" alt="Cover"/></div><h1>The Harbour Tales</h1></body></html>
    """

    static let nav = """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
    <head><title>Contents</title></head>
    <body>
    <nav epub:type="landmarks"><ol><li><a href="Text/cover.xhtml">Cover page</a></li></ol></nav>
    <nav epub:type="toc" id="toc"><h1>Contents</h1><ol>
    <li><a href="Text/chapter%201.xhtml">Opening</a></li>
    <li><a href="Text/ch2.xhtml#start">The <em>Second</em> Part</a></li>
    </ol></nav>
    </body></html>
    """

    static let opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
        <dc:identifier id="uid">urn:uuid:12345678-1234-1234-1234-123456789abc</dc:identifier>
        <dc:title>The Harbour Tales</dc:title>
        <dc:creator opf:role="aut">Ada Example</dc:creator>
        <dc:creator>Ben Sample</dc:creator>
        <dc:language>en</dc:language>
      </metadata>
      <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="cover" href="Text/cover.xhtml" media-type="application/xhtml+xml"/>
        <item id="c1" href="Text/chapter%201.xhtml" media-type="application/xhtml+xml"/>
        <item id="c2" href="./Text/../Text/ch2.xhtml" media-type="application/xhtml+xml"/>
        <item id="notes" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>
        <item id="css" href="Styles/book.css" media-type="text/css"/>
      </manifest>
      <spine>
        <itemref idref="cover"/>
        <itemref idref="c1"/>
        <itemref idref="c2"/>
        <itemref idref="notes" linear="no"/>
      </spine>
    </package>
    """

    static let container = """
    <?xml version="1.0" encoding="UTF-8"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    static func write(to url: URL, extraEntries: [(String, String)] = []) throws {
        var entries: [(path: String, data: Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/nav.xhtml", Data(nav.utf8)),
            ("OEBPS/Text/cover.xhtml", Data(cover.utf8)),
            ("OEBPS/Text/chapter 1.xhtml", Data(chapterOne.utf8)),
            ("OEBPS/Text/ch2.xhtml", Data(chapterTwo.utf8)),
            ("OEBPS/Text/notes.xhtml", Data("<html><body><p>Notes that are not in the linear reading order.</p></body></html>".utf8)),
            ("OEBPS/Styles/book.css", Data("p { margin: 0; }".utf8)),
        ]
        for (path, text) in extraEntries {
            entries.append((path, Data(text.utf8)))
        }
        try ZipWriter.write(entries: entries, to: url)
    }
}

final class EPUBTests: XCTestCase {
    func testPathResolution() {
        XCTAssertEqual(EPUBPath.directory(of: "OEBPS/content.opf"), "OEBPS")
        XCTAssertEqual(EPUBPath.directory(of: "content.opf"), "")
        XCTAssertEqual(EPUBPath.resolve("Text/ch1.xhtml", relativeTo: "OEBPS"), "OEBPS/Text/ch1.xhtml")
        XCTAssertEqual(EPUBPath.resolve("../Text/chapter%201.xhtml#p3", relativeTo: "OEBPS/Styles"), "OEBPS/Text/chapter 1.xhtml")
        XCTAssertEqual(EPUBPath.resolve("./a/./b/../c.xhtml", relativeTo: "OPS"), "OPS/a/c.xhtml")
        XCTAssertEqual(EPUBPath.resolve("/root.xhtml", relativeTo: "OPS/deep"), "root.xhtml")
        XCTAssertEqual(EPUBPath.resolve("ch.xhtml?x=1", relativeTo: ""), "ch.xhtml")
        XCTAssertEqual(EPUBPath.resolve("../../../escape.xhtml", relativeTo: "A"), "escape.xhtml")
        XCTAssertEqual(EPUBPath.resolve("caf%C3%A9.xhtml", relativeTo: "Text"), "Text/caf\u{00E9}.xhtml")
        XCTAssertEqual(EPUBPath.fragment(of: "ch2.xhtml#start"), "start")
        XCTAssertNil(EPUBPath.fragment(of: "ch2.xhtml"))
    }

    func testContainerParsing() {
        XCTAssertEqual(OPFParser.rootfilePath(containerXML: EPUBFixture.container), "OEBPS/content.opf")
    }

    func testOPFParsing() {
        let package = OPFParser.parse(opf: EPUBFixture.opf, opfPath: "OEBPS/content.opf")
        XCTAssertEqual(package.title, "The Harbour Tales")
        XCTAssertEqual(package.authors, ["Ada Example", "Ben Sample"])
        XCTAssertEqual(package.manifest.count, 6)
        XCTAssertEqual(package.manifest["c1"]?.path, "OEBPS/Text/chapter 1.xhtml")
        XCTAssertEqual(package.manifest["css"]?.mediaType, "text/css")
        XCTAssertEqual(package.spinePaths, [
            "OEBPS/Text/cover.xhtml",
            "OEBPS/Text/chapter 1.xhtml",
            "OEBPS/Text/ch2.xhtml",
        ], "Non-linear items are skipped; paths are resolved")
        XCTAssertEqual(package.navPath, "OEBPS/nav.xhtml")
    }

    func testEPUB2NCXAndPrefixedOPF() {
        let opf = """
        <opf:package xmlns:opf="http://www.idpf.org/2007/opf" version="2.0">
        <opf:metadata><dc:title>Old Style</dc:title></opf:metadata>
        <opf:manifest>
        <opf:item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        <opf:item id="a" href="a.html" media-type="application/xhtml+xml"/>
        </opf:manifest>
        <opf:spine toc="ncx"><opf:itemref idref="a"/></opf:spine>
        </opf:package>
        """
        let package = OPFParser.parse(opf: opf, opfPath: "content.opf")
        XCTAssertEqual(package.title, "Old Style")
        XCTAssertEqual(package.authors, [])
        XCTAssertEqual(package.ncxPath, "toc.ncx")
        XCTAssertEqual(package.spinePaths, ["a.html"])

        let ncx = """
        <ncx><navMap>
        <navPoint id="n1"><navLabel><text>First Chapter</text></navLabel><content src="a.html#top"/>
          <navPoint id="n2"><navLabel><text>Sub</text></navLabel><content src="a.html#sub"/></navPoint>
        </navPoint>
        <navPoint id="n3"><navLabel><text>Second &amp; Last</text></navLabel><content src="b.html"/></navPoint>
        </navMap></ncx>
        """
        XCTAssertEqual(EPUBNavigationParser.labels(ncx: ncx, ncxPath: "toc.ncx"), [
            "a.html": "First Chapter",
            "b.html": "Second & Last",
        ])
    }

    func testNavigationDocumentLabels() {
        let labels = EPUBNavigationParser.labels(navDocument: EPUBFixture.nav, navPath: "OEBPS/nav.xhtml")
        XCTAssertEqual(labels, [
            "OEBPS/Text/chapter 1.xhtml": "Opening",
            "OEBPS/Text/ch2.xhtml": "The Second Part",
        ])
    }

    func testFullImportEndToEnd() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("harbour.epub")
        try EPUBFixture.write(to: url)

        let parsed = try BookImporter.parse(url: url) { _ in }
        XCTAssertEqual(parsed.title, "The Harbour Tales")
        XCTAssertEqual(parsed.author, "Ada Example, Ben Sample")
        XCTAssertEqual(parsed.format, .epub)
        XCTAssertFalse(parsed.passagesOnly)
        XCTAssertEqual(parsed.paragraphs, [
            ParsedParagraph(text: "The harbour was full of small boats that morning, and the gulls & the fishermen argued over every crate.", chapter: "Chapter One"),
            ParsedParagraph(text: "\u{201C}Is it always like this?\u{201D} asked Mara.", chapter: "Chapter One"),
            ParsedParagraph(text: "\u{201C}Only on market days.\u{201D}", chapter: "Chapter One"),
            ParsedParagraph(text: "The tide turned at noon\u{2014}quietly, the way it always did\u{2014}and the boats began to lean against their ropes.", chapter: "Chapter One"),
            ParsedParagraph(text: "Salt on the wind,\nsalt on the stone,\nsalt in the bread\nwe carry home.", chapter: "Chapter One"),
            ParsedParagraph(text: "Mara walked up the hill behind the harbour, past the chapel and the long white wall of the cemetery.", chapter: "The Second Part"),
            ParsedParagraph(text: "From the top she could see the whole bay, the islands, and the grey line of the far coast.", chapter: "The Second Part"),
            ParsedParagraph(text: "She stayed there until the light went, counting the boats as they came home one by one.", chapter: "The Second Part"),
        ], "Cover skipped (under 40 words), scene break dropped, heading and navigation labels applied")

        let container = try Fixtures.makeContainer()
        var reported: [Double] = []
        let bookID = try BookImporter.importBook(at: url, into: container) { reported.append($0) }
        XCTAssertEqual(reported.last, 1)

        let store = LibraryStore(context: ModelContext(container))
        let book = try XCTUnwrap(store.book(id: bookID))
        let segmented = Segmenter.segment(parsed.paragraphs)
        XCTAssertEqual(book.title, "The Harbour Tales")
        XCTAssertEqual(book.author, "Ada Example, Ben Sample")
        XCTAssertEqual(book.format, .epub)
        XCTAssertEqual(book.totalCharacters, segmented.totalCharacters)
        XCTAssertEqual(book.paragraphSegmentCount, 8)
        XCTAssertEqual(book.passageSegmentCount, segmented.passages.count)
        XCTAssertEqual(book.positionOffset, 0)

        let feedBook = FeedBook(book)
        let stored = store.segments(book: feedBook, style: .paragraph, from: 0, limit: 100)
        XCTAssertEqual(stored.map(\.text), parsed.paragraphs.map(\.text))
        XCTAssertEqual(stored.map(\.index), Array(0..<8))
        let storedPassages = store.segments(book: feedBook, style: .passage, from: 0, limit: 100)
        XCTAssertEqual(storedPassages.count, segmented.passages.count)
        XCTAssertEqual(store.segments(book: feedBook, style: .paragraph, from: 3, limit: 2).map(\.index), [3, 4])
        XCTAssertEqual(store.segments(book: feedBook, style: .paragraph, before: 3, limit: 2).map(\.index), [1, 2])

        for segment in stored {
            for offset in [segment.charStart, (segment.charStart + segment.charEnd) / 2, segment.charEnd - 1] {
                XCTAssertEqual(store.indexContaining(offset: offset, book: feedBook, style: .paragraph), segment.index)
            }
        }
        for segment in storedPassages {
            XCTAssertEqual(store.indexContaining(offset: segment.charEnd - 1, book: feedBook, style: .passage), segment.index)
        }

        // The same book again is rejected as a duplicate.
        XCTAssertThrowsError(try BookImporter.importBook(at: url, into: container)) { error in
            XCTAssertEqual(error as? BookImportError, .duplicate("The Harbour Tales"))
        }

        // A different book gets its own keys and does not collide.
        var other = parsed
        other.title = "Another Book"
        let secondID = try BookWriter.write(parsed: other, segmented: segmented, into: ModelContext(container))
        XCTAssertNotEqual(secondID, bookID)
        XCTAssertEqual(store.allBooks().count, 2)

        // Deleting removes the book, its segments and its marks.
        store.addMark(kind: .like, bookID: bookID, charStart: 0, charEnd: 10)
        try store.deleteBook(id: bookID)
        XCTAssertNil(store.book(id: bookID))
        let remaining = try ModelContext(container).fetch(FetchDescriptor<Segment>())
        XCTAssertTrue(remaining.allSatisfy { $0.bookID == secondID })
        XCTAssertEqual(remaining.count, segmented.paragraphs.count + segmented.passages.count)
        XCTAssertTrue(store.allMarks().isEmpty)
    }

    func testDRMProtectedEPUBIsRejected() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let fairPlay = folder.appendingPathComponent("fairplay.epub")
        try EPUBFixture.write(to: fairPlay, extraEntries: [("META-INF/sinf.xml", "<fairplay/>")])
        XCTAssertThrowsError(try BookImporter.parse(url: fairPlay) { _ in }) { error in
            XCTAssertEqual(error as? BookImportError, .drmProtected)
        }

        let encrypted = folder.appendingPathComponent("encrypted.epub")
        let encryption = """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
        <enc:CipherData><enc:CipherReference URI="OEBPS/Text/ch2.xhtml"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """
        try EPUBFixture.write(to: encrypted, extraEntries: [("META-INF/encryption.xml", encryption)])
        XCTAssertThrowsError(try BookImporter.parse(url: encrypted) { _ in }) { error in
            XCTAssertEqual(error as? BookImportError, .drmProtected)
        }

        let fonts = folder.appendingPathComponent("fonts.epub")
        let obfuscation = """
        <encryption xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
        <enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
        <enc:CipherData><enc:CipherReference URI="OEBPS/Fonts/serif.otf"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """
        try EPUBFixture.write(to: fonts, extraEntries: [("META-INF/encryption.xml", obfuscation)])
        XCTAssertNoThrow(try BookImporter.parse(url: fonts) { _ in }, "Font obfuscation is not DRM")
    }

    func testUnreadableFilesGiveClearErrors() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let garbage = folder.appendingPathComponent("broken.epub")
        try Data("this is not a zip file".utf8).write(to: garbage)
        XCTAssertThrowsError(try BookImporter.parse(url: garbage) { _ in }) { error in
            guard case .unreadable = error as? BookImportError else {
                return XCTFail("Expected unreadable, got \(error)")
            }
        }

        let text = folder.appendingPathComponent("notes.txt")
        try Data("plain text".utf8).write(to: text)
        XCTAssertThrowsError(try BookImporter.parse(url: text) { _ in }) { error in
            XCTAssertEqual(error as? BookImportError, .unsupportedFormat)
        }

        let noContainer = folder.appendingPathComponent("nocontainer.epub")
        try ZipWriter.write(entries: [("mimetype", Data("application/epub+zip".utf8))], to: noContainer)
        XCTAssertThrowsError(try BookImporter.parse(url: noContainer) { _ in }) { error in
            guard case .unreadable = error as? BookImportError else {
                return XCTFail("Expected unreadable, got \(error)")
            }
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
