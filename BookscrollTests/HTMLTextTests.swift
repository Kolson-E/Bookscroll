import XCTest
@testable import Bookscroll

final class HTMLTextTests: XCTestCase {
    func testStripsInlineTagsAndCollapsesWhitespace() {
        let html = "<p>The <em>quick</em>   brown\n\t<span class=\"x\">fox</span> <a href='#'>jumps</a>.</p>"
        XCTAssertEqual(HTMLTextExtractor.blocks(from: html), [HTMLBlock(text: "The quick brown fox jumps.", headingLevel: nil)])
    }

    func testEachBlockElementIsOneParagraph() {
        let html = """
        <body>
          <div><p>First.</p><p>Second.</p></div>
          <blockquote>Quoted words.</blockquote>
          <ul><li>Item one</li><li>Item two</li></ul>
          <div>Loose div text</div>
        </body>
        """
        let texts = HTMLTextExtractor.blocks(from: html).map(\.text)
        XCTAssertEqual(texts, ["First.", "Second.", "Quoted words.", "Item one", "Item two", "Loose div text"])
    }

    func testBreakIsLineBreakInsideParagraph() {
        let html = "<p class=\"verse\">Line one,<br/>line two,<br>  line three.</p>"
        XCTAssertEqual(HTMLTextExtractor.blocks(from: html).map(\.text), ["Line one,\nline two,\nline three."])
    }

    func testNamedEntities() {
        XCTAssertEqual(HTMLEntities.decode("Fish &amp; chips &mdash; &lsquo;yes&rsquo; &lt;b&gt; caf&eacute;"),
                       "Fish & chips \u{2014} \u{2018}yes\u{2019} <b> caf\u{00E9}")
        XCTAssertEqual(HTMLEntities.decode("a&nbsp;b"), "a\u{00A0}b")
        XCTAssertEqual(HTMLEntities.decode("&unknown; & &amp"), "&unknown; & &amp")
    }

    func testNumericEntities() {
        XCTAssertEqual(HTMLEntities.decode("&#8220;Hi&#8221; &#x2014; &#X41;&#65;"), "\u{201C}Hi\u{201D} \u{2014} AA")
        XCTAssertEqual(HTMLEntities.decode("&#151;"), "\u{2014}", "Windows-1252 code points map to Unicode")
        XCTAssertEqual(HTMLEntities.decode("&#128512;"), "\u{1F600}")
    }

    func testEntitiesInsideParagraphs() {
        let html = "<p>Tom&#160;&amp;&nbsp;Jerry said &#8220;Hello&#8221;.</p>"
        XCTAssertEqual(HTMLTextExtractor.blocks(from: html).map(\.text), ["Tom & Jerry said \u{201C}Hello\u{201D}."])
    }

    func testRemovesHeadScriptAndStyle() {
        let html = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Should not appear</title>
        <style>p { color: red; } /* <p>not text</p> */</style>
        <script type="text/javascript">var x = "<p>nope</p>"; if (a < b) {}</script>
        </head>
        <body>
        <!-- a comment <p>hidden</p> -->
        <p>Visible text.</p>
        <script>document.write("<p>also hidden</p>")</script>
        <p>More <![CDATA[raw & text]]>.</p>
        </body></html>
        """
        XCTAssertEqual(HTMLTextExtractor.blocks(from: html).map(\.text), ["Visible text.", "More raw & text."])
    }

    func testHeadingExtraction() {
        let html = """
        <h1 class="chapter"><span>Chapter</span> <span>One</span></h1>
        <p>Body.</p>
        <h3>A Section</h3>
        <h6>Tiny</h6>
        """
        let blocks = HTMLTextExtractor.blocks(from: html)
        XCTAssertEqual(blocks, [
            HTMLBlock(text: "Chapter One", headingLevel: 1),
            HTMLBlock(text: "Body.", headingLevel: nil),
            HTMLBlock(text: "A Section", headingLevel: 3),
            HTMLBlock(text: "Tiny", headingLevel: 6),
        ])
    }

    func testTokenizerAttributes() {
        let tokens = HTMLTokenizer.tokenize("<item id=\"c1\" href='Text/a%20b.xhtml' media-type=application/xhtml+xml properties=\"nav scripted\"/>")
        XCTAssertEqual(tokens, [
            .start(name: "item", attributes: [
                "id": "c1",
                "href": "Text/a%20b.xhtml",
                "media-type": "application/xhtml+xml",
                "properties": "nav scripted",
            ], selfClosing: true),
        ])
    }

    func testMalformedMarkupDoesNotCrash() {
        let html = "<p>Unclosed <b>bold <p>Next < 3 and 4 > 2</div></span><"
        let texts = HTMLTextExtractor.blocks(from: html).map(\.text)
        XCTAssertEqual(texts, ["Unclosed bold", "Next < 3 and 4 > 2", "<"])
    }
}
