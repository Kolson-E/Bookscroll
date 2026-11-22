import PDFKit
import UIKit
import XCTest
@testable import Bookscroll

/// Generates a two-page PDF with known paragraphs. Each page has a running header and a page
/// number footer. Paragraph breaks are marked three ways: indent, vertical gap, and a short
/// line ending in a full stop. One word is hyphenated across lines, one paragraph crosses the
/// page break.
enum PDFFixture {
    struct Paragraph {
        var lines: [String]
        var indented: Bool
        var gapBefore: CGFloat = 0
    }

    static let header = "The Fixture Book"
    static let pageSize = CGSize(width: 612, height: 792)
    static let lineHeight: CGFloat = 16
    static let bodyTop: CGFloat = 150

    static let pageOne: [Paragraph] = [
        Paragraph(lines: [
            "The morning light came slowly over the hills, and the old road was quiet",
            "while the travelers packed their bags and talked about the long day ahead",
            "of them as the sun rose.",
        ], indented: true),
        Paragraph(lines: [
            "Nobody in the village could remember a more remarkable experi-",
            "ment than the one the young baker tried that summer with honey and",
            "salt and a great deal of patience.",
        ], indented: true),
        Paragraph(lines: [
            "A gap without any indent also marks the start of a new paragraph in this",
            "short block of text.",
        ], indented: false, gapBefore: 14),
        Paragraph(lines: [
            "This paragraph begins right after a short line that ended with a full",
            "stop, and it continues onto the next page without any break in the text",
        ], indented: false),
    ]

    static let pageTwo: [Paragraph] = [
        Paragraph(lines: [
            "at all, which means the two halves must be joined together again.",
        ], indented: false),
        Paragraph(lines: [
            "The second page has its own header and its own page number at the bottom,",
            "and both of them must be removed before the paragraphs are rebuilt by the",
            "detector, because they are not part of the story that the reader wants to",
            "see in the timeline.",
        ], indented: true),
        Paragraph(lines: [
            "Short closing words.",
        ], indented: true),
    ]

    static let expectedParagraphs = [
        "The morning light came slowly over the hills, and the old road was quiet while the travelers packed their bags and talked about the long day ahead of them as the sun rose.",
        "Nobody in the village could remember a more remarkable experiment than the one the young baker tried that summer with honey and salt and a great deal of patience.",
        "A gap without any indent also marks the start of a new paragraph in this short block of text.",
        "This paragraph begins right after a short line that ended with a full stop, and it continues onto the next page without any break in the text at all, which means the two halves must be joined together again.",
        "The second page has its own header and its own page number at the bottom, and both of them must be removed before the paragraphs are rebuilt by the detector, because they are not part of the story that the reader wants to see in the timeline.",
        "Short closing words.",
    ]

    static func write(to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let font = UIFont(name: "Helvetica", size: 12) ?? UIFont.systemFont(ofSize: 12)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .ligature: 0,
        ]
        try renderer.writePDF(to: url) { context in
            for (pageIndex, paragraphs) in [pageOne, pageTwo].enumerated() {
                context.beginPage()
                (header as NSString).draw(at: CGPoint(x: 72, y: 40), withAttributes: attributes)
                ("\(pageIndex + 1)" as NSString).draw(at: CGPoint(x: 300, y: 740), withAttributes: attributes)
                var y = bodyTop
                for paragraph in paragraphs {
                    y += paragraph.gapBefore
                    for (lineIndex, line) in paragraph.lines.enumerated() {
                        let x: CGFloat = (lineIndex == 0 && paragraph.indented) ? 92 : 72
                        (line as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
                        y += lineHeight
                    }
                }
            }
        }
    }

    /// Copies the PDF and adds an outline: "Part One" at the top of page 1, "Part Two" on page 2.
    static func writeWithOutline(from source: URL, to destination: URL) throws {
        let document = try XCTUnwrap(PDFDocument(url: source))
        let root = PDFOutline()
        let labels = ["Part One", "Part Two"]
        for (index, label) in labels.enumerated() {
            let item = PDFOutline()
            item.label = label
            let page = try XCTUnwrap(document.page(at: index))
            item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 700))
            root.insertChild(item, at: index)
        }
        document.outlineRoot = root
        XCTAssertTrue(document.write(to: destination))
    }

    static func writeScanned(to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        try renderer.writePDF(to: url) { context in
            for _ in 0..<2 {
                context.beginPage()
                UIColor.darkGray.setFill()
                UIRectFill(CGRect(x: 72, y: 72, width: 468, height: 600))
            }
        }
    }
}

final class PDFTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testParagraphDetectionOnGeneratedPDF() throws {
        let url = folder.appendingPathComponent("fixture.pdf")
        try PDFFixture.write(to: url)
        let parsed = try BookImporter.parse(url: url) { _ in }
        XCTAssertEqual(parsed.format, .pdf)
        XCTAssertEqual(parsed.paragraphs.map(\.text), PDFFixture.expectedParagraphs)
        XCTAssertFalse(parsed.passagesOnly)
        XCTAssertFalse(parsed.paragraphs.contains { $0.text.contains(PDFFixture.header) }, "Running header removed")
        XCTAssertEqual(parsed.paragraphs.map(\.chapter), Array(repeating: "", count: 6), "No outline, no chapter labels")
    }

    func testRunningHeadersAndFootersRemoved() throws {
        let url = folder.appendingPathComponent("fixture.pdf")
        try PDFFixture.write(to: url)
        let document = try XCTUnwrap(PDFDocument(url: url))
        let pages = (0..<document.pageCount).map { index -> PDFPageLines in
            let page = document.page(at: index)!
            return PDFPageLines(lines: PDFBookParser.extractLines(from: page), height: page.bounds(for: .mediaBox).height)
        }
        XCTAssertTrue(pages[0].lines.contains { $0.text == PDFFixture.header })
        XCTAssertTrue(pages[1].lines.contains { $0.text == "2" })
        let cleaned = PDFParagraphDetector.removeRunningHeadersAndFooters(pages)
        for page in cleaned {
            XCTAssertFalse(page.lines.contains { $0.text == PDFFixture.header })
            XCTAssertFalse(page.lines.contains { $0.text == "1" || $0.text == "2" })
        }
        XCTAssertEqual(cleaned[0].lines.count, pages[0].lines.count - 2)
    }

    func testOutlineGivesChapterLabels() throws {
        let plain = folder.appendingPathComponent("plain.pdf")
        let outlined = folder.appendingPathComponent("outlined.pdf")
        try PDFFixture.write(to: plain)
        try PDFFixture.writeWithOutline(from: plain, to: outlined)
        let parsed = try BookImporter.parse(url: outlined) { _ in }
        XCTAssertEqual(parsed.paragraphs.map(\.text), PDFFixture.expectedParagraphs)
        XCTAssertEqual(parsed.paragraphs.map(\.chapter), [
            "Part One", "Part One", "Part One", "Part One", "Part Two", "Part Two",
        ])
    }

    func testScannedPDFIsRejected() throws {
        let url = folder.appendingPathComponent("scan.pdf")
        try PDFFixture.writeScanned(to: url)
        XCTAssertThrowsError(try BookImporter.parse(url: url) { _ in }) { error in
            XCTAssertEqual(error as? BookImportError, .scannedPDF)
        }
    }

    func testHyphenationAndWrapJoining() {
        XCTAssertEqual(PDFParagraphDetector.joinLines(["an experi-", "ment in", "time"]), "an experiment in time")
        XCTAssertEqual(PDFParagraphDetector.joinLines(["well-", "Known"]), "well-Known", "Capitalised continuation keeps the hyphen")
        XCTAssertEqual(PDFParagraphDetector.joinLines(["soft\u{00AD}", "hyphen"]), "softhyphen")
        XCTAssertEqual(PDFParagraphDetector.joinLines(["a dash\u{2014}", "and more"]), "a dash\u{2014}and more")
    }

    func testDetectorRulesOnSyntheticLines() {
        func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> PDFTextLine {
            PDFTextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: 12))
        }
        let page = PDFPageLines(lines: [
            line("First paragraph line one goes on", x: 72, y: 700, width: 400),
            line("and ends here.", x: 72, y: 686, width: 100),
            line("Second paragraph after a short line", x: 72, y: 672, width: 400),
            line("continues on", x: 72, y: 658, width: 400),
            line("Third after a gap", x: 72, y: 620, width: 400),
            line("still third", x: 72, y: 606, width: 400),
            line("Fourth is indented", x: 100, y: 592, width: 372),
            line("and wraps.", x: 72, y: 578, width: 400),
        ], height: 792)
        XCTAssertEqual(PDFParagraphDetector.detect([page]).map(\.text), [
            "First paragraph line one goes on and ends here.",
            "Second paragraph after a short line continues on",
            "Third after a gap still third",
            "Fourth is indented and wraps.",
        ])
    }

    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 12) -> PDFTextLine {
        PDFTextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height))
    }

    func testTwoColumnPageIsReadInColumnOrder() {
        let left = ["The left column starts here and", "runs down the page in lines", "that wrap as columns do and", "go on at the top of the right"]
        let right = ["column, where the sentence ends", "with more words and more lines", "until the paragraph is done at", "the bottom of the page."]
        // PDFKit can return the two columns interleaved, row by row.
        var lines = [line("A Two Column Page", x: 150, y: 720, width: 300)]
        for row in 0..<4 {
            let y = 650 - CGFloat(row) * 14
            lines.append(line(left[row], x: 50, y: y, width: 230))
            lines.append(line(right[row], x: 320, y: y, width: row == 3 ? 150 : 230))
        }
        let page = PDFPageLines(lines: lines, height: 792, width: 600)
        let ordered = PDFParagraphDetector.readingOrder(page)
        XCTAssertEqual(ordered.lines.map(\.text), ["A Two Column Page"] + left + right)
        XCTAssertEqual(ordered.lines.last?.rect.minX, 50, "The right column moves onto the left margin")
        XCTAssertEqual(PDFParagraphDetector.detect([ordered]).map(\.text), [
            "A Two Column Page",
            (left + right).joined(separator: " "),
        ])

        let oneColumn = PDFPageLines(lines: (0..<8).map { line("Line \($0) of a single column", x: 72, y: 700 - CGFloat($0) * 14, width: 450) }, height: 792, width: 612)
        XCTAssertEqual(PDFParagraphDetector.readingOrder(oneColumn), oneColumn)
    }

    private var headingPage: PDFPageLines {
        PDFPageLines(lines: [
            line("Chapter One", x: 72, y: 700, width: 150, height: 24),
            line("The first paragraph of the first chapter is", x: 72, y: 660, width: 400),
            line("here.", x: 72, y: 646, width: 40),
            line("A second paragraph, indented.", x: 92, y: 632, width: 380),
            line("Chapter Two", x: 72, y: 590, width: 150, height: 24),
            line("The second chapter starts with this line and", x: 72, y: 550, width: 400),
            line("ends here.", x: 72, y: 536, width: 80),
            line("Its last paragraph.", x: 92, y: 522, width: 380),
        ], height: 792, width: 612)
    }

    func testLargeShortLinesBecomeChaptersWithoutAnOutline() {
        let detected = PDFParagraphDetector.detect([headingPage])
        XCTAssertEqual(detected.filter(\.isHeading).map(\.text), ["Chapter One", "Chapter Two"])
        XCTAssertEqual(PDFBookParser.assignChapters(detected, outline: []), [
            ParsedParagraph(text: "The first paragraph of the first chapter is here.", chapter: "Chapter One"),
            ParsedParagraph(text: "A second paragraph, indented.", chapter: "Chapter One"),
            ParsedParagraph(text: "The second chapter starts with this line and ends here.", chapter: "Chapter Two"),
            ParsedParagraph(text: "Its last paragraph.", chapter: "Chapter Two"),
        ])
    }

    func testAHeadingThatRepeatsItsOutlineLabelIsDropped() {
        let detected = PDFParagraphDetector.detect([headingPage])
        let outline = [PDFBookParser.OutlineEntry(label: "CHAPTER ONE", pageIndex: 0, y: 724)]
        XCTAssertEqual(PDFBookParser.assignChapters(detected, outline: outline).map(\.text), [
            "The first paragraph of the first chapter is here.",
            "A second paragraph, indented.",
            "Chapter Two",
            "The second chapter starts with this line and ends here.",
            "Its last paragraph.",
        ])
    }

    func testTypeSizeIsIgnoredWhenTooManyLinesAreLarge() {
        let page = PDFPageLines(lines: [
            line("Big One", x: 72, y: 700, width: 150, height: 24),
            line("A body line.", x: 72, y: 660, width: 400),
            line("Big Two", x: 72, y: 620, width: 150, height: 24),
            line("Another body line.", x: 72, y: 580, width: 400),
        ], height: 792, width: 612)
        let paragraphs = PDFBookParser.assignChapters(PDFParagraphDetector.detect([page]), outline: [])
        XCTAssertEqual(paragraphs.map(\.text), ["Big One", "A body line.", "Big Two", "Another body line."])
        XCTAssertEqual(Set(paragraphs.map(\.chapter)), [""])
    }

    func testDropCapJoinsItsWord() {
        let page = PDFPageLines(lines: [
            line("T", x: 50, y: 660, width: 22, height: 30),
            line("he river ran fast under the old stone bridge and", x: 80, y: 676, width: 400),
            line("nobody in the town could remember when it was", x: 80, y: 662, width: 400),
            line("built, or by whom, so long ago was it built there.", x: 50, y: 648, width: 430),
            line("A second paragraph begins with an indent", x: 70, y: 634, width: 410),
            line("and ends.", x: 50, y: 620, width: 80),
        ], height: 792, width: 612)
        XCTAssertEqual(PDFParagraphDetector.detect([page]).map(\.text), [
            "The river ran fast under the old stone bridge and nobody in the town could remember when it was built, or by whom, so long ago was it built there.",
            "A second paragraph begins with an indent and ends.",
        ])
    }

    func testLigaturesBecomeLetters() {
        XCTAssertEqual(PDFParagraphDetector.joinLines(["The \u{FB01}rst \u{FB02}oor was", "e\u{FB03}cient"]), "The first floor was efficient")
        XCTAssertEqual(PDFParagraphDetector.normalizeGlyphs("o\u{FB00} and wa\u{FB04}e and \u{FB06}op"), "off and waffle and stop")
        XCTAssertEqual(PDFParagraphDetector.normalizeGlyphs("plain"), "plain")
    }

    func testLongParagraphsForcePassages() {
        let long = String(repeating: "word ", count: 350)
        XCTAssertTrue(PDFBookParser.shouldForcePassages([ParsedParagraph(text: long, chapter: "")]))
        XCTAssertFalse(PDFBookParser.shouldForcePassages([ParsedParagraph(text: "A short one.", chapter: "")]))
    }
}
