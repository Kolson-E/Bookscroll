import Foundation

/// One block of text from an (X)HTML document, or an image.
struct HTMLBlock: Equatable {
    var text: String
    /// 1...6 for h1–h6, nil for body text.
    var headingLevel: Int?
    /// Set on an image block (its text is empty).
    var image: HTMLImage? = nil

    var isHeading: Bool { headingLevel != nil }
}

/// An image in an (X)HTML document: `img src`, or an SVG `image` (`xlink:href`).
struct HTMLImage: Equatable {
    /// The reference as written in the document.
    var source: String
    /// The image's alternative text; may be empty.
    var alt: String
}

/// Converts (X)HTML to a list of blocks.
///
/// Rules:
/// - `head`, `script`, `style`, `noscript` and `template` are removed with their content.
/// - Each block element (`p`, `div`, `blockquote`, `li`, `h1`–`h6`, plus structural containers)
///   ends the current block, so each one becomes its own paragraph. Nested blocks never merge.
/// - `br` is a line break inside the current block.
/// - Runs of whitespace collapse to one space. Character references are decoded.
/// - With `images`, each image becomes an image block right after the block it is in, so an
///   image inside a paragraph comes after the paragraph's text.
enum HTMLTextExtractor {
    static let paragraphElements: Set<String> = [
        "p", "div", "blockquote", "li", "h1", "h2", "h3", "h4", "h5", "h6",
    ]

    static let boundaryElements: Set<String> = paragraphElements.union([
        "html", "body", "section", "article", "aside", "header", "footer", "nav", "main",
        "ul", "ol", "dl", "dt", "dd", "table", "thead", "tbody", "tfoot", "tr", "td", "th",
        "caption", "figure", "figcaption", "pre", "address", "hgroup", "center", "details",
        "summary", "hr",
    ])

    static let skippedElements: Set<String> = ["head", "script", "style", "noscript", "template"]

    static func blocks(from html: String, images: Bool = false) -> [HTMLBlock] {
        var builder = BlockBuilder()
        var skipStack: [String] = []

        for token in HTMLTokenizer.tokenize(html) {
            if !skipStack.isEmpty {
                switch token {
                case let .start(name, _, selfClosing):
                    if name == "body" {
                        // Unclosed head in sloppy HTML: the body still counts.
                        skipStack.removeAll()
                        builder.open("body")
                    } else if skippedElements.contains(name) && !selfClosing {
                        skipStack.append(name)
                    }
                case let .end(name):
                    if let index = skipStack.lastIndex(of: name) {
                        skipStack.removeSubrange(index...)
                    }
                case .text:
                    break
                }
                continue
            }

            switch token {
            case let .start(name, attributes, selfClosing):
                if skippedElements.contains(name) {
                    if !selfClosing { skipStack.append(name) }
                } else if name == "br" {
                    builder.lineBreak()
                } else if images, let image = image(name: name, attributes: attributes) {
                    builder.addImage(image)
                } else if boundaryElements.contains(name) {
                    builder.flush()
                    if !selfClosing && name != "hr" {
                        builder.open(name)
                    }
                }
            case let .end(name):
                if boundaryElements.contains(name) {
                    builder.flush()
                    builder.close(name)
                }
            case let .text(text):
                builder.append(text)
            }
        }
        builder.flush()
        return builder.blocks
    }

    /// The image an `img` or SVG `image` element shows. Inline `data:` images are left out.
    static func image(name: String, attributes: [String: String]) -> HTMLImage? {
        let source: String?
        switch OPFParser.localName(name) {
        case "img": source = attributes["src"]
        case "image": source = attributes["xlink:href"] ?? attributes["href"]
        default: return nil
        }
        guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty,
              !source.lowercased().hasPrefix("data:") else { return nil }
        let alt = TextUtils.singleLine(attributes["alt"] ?? "")
        return HTMLImage(source: source, alt: alt)
    }

    static func headingLevel(of element: String) -> Int? {
        guard element.count == 2, element.first == "h", let digit = element.last?.wholeNumberValue,
              (1...6).contains(digit) else { return nil }
        return digit
    }
}

private struct BlockBuilder {
    var blocks: [HTMLBlock] = []
    private var buffer = String.UnicodeScalarView()
    private var pendingSpace = false
    private var stack: [String] = []
    private var preformattedDepth = 0
    /// Images met inside the current block: they follow its text.
    private var pendingImages: [HTMLImage] = []

    mutating func addImage(_ image: HTMLImage) {
        pendingImages.append(image)
    }

    mutating func open(_ name: String) {
        stack.append(name)
        if name == "pre" { preformattedDepth += 1 }
    }

    mutating func close(_ name: String) {
        guard let index = stack.lastIndex(of: name) else { return }
        preformattedDepth -= stack[index...].filter { $0 == "pre" }.count
        stack.removeSubrange(index...)
    }

    mutating func append(_ text: String) {
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n" where preformattedDepth > 0:
                lineBreak()
            case " ", "\t", "\n", "\r", "\u{0C}", "\u{00A0}":
                pendingSpace = true
            case "\u{00AD}":
                continue
            default:
                if pendingSpace, let last = buffer.last, last != "\n" {
                    buffer.append(" ")
                }
                pendingSpace = false
                buffer.append(scalar)
            }
        }
    }

    mutating func lineBreak() {
        pendingSpace = false
        if let last = buffer.last, last != "\n" {
            buffer.append("\n")
        }
    }

    mutating func flush() {
        let text = String(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = String.UnicodeScalarView()
        pendingSpace = false
        if !text.isEmpty {
            let level = stack.reversed().lazy.compactMap(HTMLTextExtractor.headingLevel(of:)).first
            blocks.append(HTMLBlock(text: text, headingLevel: level))
        }
        for image in pendingImages {
            blocks.append(HTMLBlock(text: "", headingLevel: nil, image: image))
        }
        pendingImages.removeAll()
    }
}
