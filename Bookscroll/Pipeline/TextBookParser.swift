import Foundation
import UIKit

/// Plain text, Markdown, HTML and RTF books, and text pasted into the app.
///
/// Paragraphs:
/// - Plain text: blank lines separate paragraphs; the lines inside one are joined (hard-wrapped
///   files such as Project Gutenberg texts). A file without blank lines has one paragraph per line.
/// - Markdown: as plain text, with `#` headings as chapters, list items as paragraphs, and the
///   markup (emphasis, links, images, code fences, quotes) removed.
/// - HTML: the same block rules as EPUB chapters; `h1`–`h3` are chapters.
/// - RTF: one paragraph per paragraph of the document.
///
/// Chapters in plain text: a short line on its own that starts with Chapter, Part, Book,
/// Prologue, Epilogue and similar words, or that is only a number or a Roman numeral.
enum TextBookParser {
    /// Longest line (in characters) that can be a chapter heading in plain text.
    static let maximumHeadingLength = 60

    static func parse(url: URL, format: BookFormat, fallbackTitle: String) throws -> ParsedBook {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BookImportError.unreadable("The file could not be opened.")
        }
        switch format {
        case .rtf:
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.rtf]
            guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
                throw BookImportError.unreadable("It is not a valid RTF document.")
            }
            return parsePlain(attributed.string, title: nil, author: nil, fallbackTitle: fallbackTitle, format: .rtf, linesAreParagraphs: true)
        case .html:
            guard let text = decode(data) else { throw BookImportError.unreadable("The text encoding is not supported.") }
            return parseHTML(text, fallbackTitle: fallbackTitle)
        case .markdown:
            guard let text = decode(data) else { throw BookImportError.unreadable("The text encoding is not supported.") }
            return parseMarkdown(text, fallbackTitle: fallbackTitle)
        default:
            guard let text = decode(data) else { throw BookImportError.unreadable("The text encoding is not supported.") }
            return parsePlain(text, title: nil, author: nil, fallbackTitle: fallbackTitle, format: .text)
        }
    }

    /// Text pasted into the app. Empty title or author fall back to "Pasted text" and
    /// "Unknown author".
    static func parsePasted(_ text: String, title: String, author: String) -> ParsedBook {
        let title = TextUtils.singleLine(title)
        let author = TextUtils.singleLine(author)
        return parsePlain(
            text,
            title: title.isEmpty ? nil : title,
            author: author.isEmpty ? nil : author,
            fallbackTitle: "Pasted text",
            format: .text
        )
    }

    // MARK: Decoding

    /// UTF-8 (with or without a byte order mark), UTF-16 with a byte order mark, else
    /// Windows-1252. Nil for data that looks binary.
    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if data.prefix(4096).contains(0) { return nil }
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let text = String(data: bytes, encoding: .utf8) { return text }
        return String(data: bytes, encoding: .windowsCP1252)
    }

    // MARK: Plain text

    static func parsePlain(
        _ raw: String,
        title: String?,
        author: String?,
        fallbackTitle: String,
        format: BookFormat,
        linesAreParagraphs: Bool = false
    ) -> ParsedBook {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let gutenberg = stripGutenbergFrame(&text)
        let lines = text.components(separatedBy: "\n")
        let blocks = linesAreParagraphs || !hasBlankLineParagraphs(lines)
            ? lines.map { [$0] }
            : splitOnBlankLines(lines)

        var paragraphs: [ParsedParagraph] = []
        var chapter = ""
        for block in blocks {
            let joined = TextUtils.singleLine(block.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
            guard !joined.isEmpty, TextUtils.hasLetterOrDigit(joined) else { continue }
            if block.count == 1, isChapterHeading(joined) {
                chapter = joined
                continue
            }
            paragraphs.append(ParsedParagraph(text: joined, chapter: chapter))
        }
        return ParsedBook(
            title: title ?? gutenberg.title ?? fallbackTitle,
            author: author ?? gutenberg.author ?? "Unknown author",
            format: format,
            paragraphs: paragraphs,
            passagesOnly: false,
            note: nil
        )
    }

    /// True when at least three blocks are separated by blank lines.
    private static func hasBlankLineParagraphs(_ lines: [String]) -> Bool {
        splitOnBlankLines(lines).count >= 3
    }

    private static func splitOnBlankLines(_ lines: [String]) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty { blocks.append(current) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    private static let headingWords = [
        "chapter", "part", "book", "volume", "section", "act", "scene", "canto", "letter",
        "prologue", "epilogue", "preface", "foreword", "introduction", "afterword", "interlude",
        "kapitel", "teil", "chapitre", "partie", "cap\u{00ED}tulo", "capitolo",
    ]

    /// Words that can follow a heading word: "Part Two", "Book the First".
    private static let numberWords: Set<String> = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty",
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth",
        "tenth", "last", "final", "the",
    ]

    /// A heading word alone ("Prologue", "Epilogue."), a heading word with a number
    /// ("Chapter 2: The Flood", "Book I", "Part Two"), a line in capitals that starts with a
    /// heading word ("CHAPTER THE FIRST"), a number ("12") or a Roman numeral ("XII.").
    /// "Part of me knew." is a sentence, not a heading.
    static func isChapterHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maximumHeadingLength else { return false }
        // A sentence is not a heading.
        if let last = trimmed.last, ",;".contains(last) { return false }
        let punctuation = CharacterSet(charactersIn: ".:-\u{2013}\u{2014}")
        let words = trimmed.split(separator: " ").map { String($0) }
        if words.count <= 10, let first = words.first {
            let firstBare = first.lowercased().trimmingCharacters(in: punctuation)
            if headingWords.contains(firstBare) {
                // The heading word ends the line or is followed by ":" or "." and a title.
                if words.count == 1 || first.last.map({ ".:".contains($0) }) == true { return true }
                let next = words[1].trimmingCharacters(in: punctuation)
                if isNumber(next) || isRomanNumeral(next) || numberWords.contains(next.lowercased()) { return true }
                if trimmed == trimmed.uppercased(), trimmed != trimmed.lowercased() { return true }
                return false
            }
        }
        let bare = trimmed.trimmingCharacters(in: punctuation)
        return isNumber(bare) || isRomanNumeral(bare)
    }

    private static func isNumber(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 6 && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// "I", "IV", "XII": a valid Roman numeral in capitals, up to 3999.
    private static func isRomanNumeral(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 12
            && text.range(of: "^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$", options: .regularExpression) != nil
    }

    /// Removes the Project Gutenberg licence before and after the text, and reads its
    /// Title and Author lines.
    private static func stripGutenbergFrame(_ text: inout String) -> (title: String?, author: String?) {
        guard let start = text.range(of: "*** START OF", options: .caseInsensitive) ?? text.range(of: "***START OF", options: .caseInsensitive) else {
            return (nil, nil)
        }
        let header = String(text[..<start.lowerBound])
        func field(_ name: String) -> String? {
            for line in header.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix(name.lowercased() + ":") {
                    let value = TextUtils.singleLine(String(trimmed.dropFirst(name.count + 1)))
                    return value.isEmpty ? nil : value
                }
            }
            return nil
        }
        let lineEnd = text[start.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        var body = String(text[lineEnd...])
        if let end = body.range(of: "*** END OF", options: .caseInsensitive) ?? body.range(of: "***END OF", options: .caseInsensitive) {
            body = String(body[..<end.lowerBound])
        }
        text = body
        return (field("Title"), field("Author"))
    }

    // MARK: Markdown

    static func parseMarkdown(_ raw: String, fallbackTitle: String) -> ParsedBook {
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var title: String?
        var author: String?
        // YAML front matter.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            for line in lines[1..<end] {
                let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                switch parts[0].lowercased() {
                case "title": title = value.isEmpty ? nil : value
                case "author": author = value.isEmpty ? nil : value
                default: break
                }
            }
            lines.removeSubrange(0...end)
        }

        var paragraphs: [ParsedParagraph] = []
        var chapter = ""
        var block: [String] = []
        var inFence = false
        var sawText = false

        func flush() {
            let text = TextUtils.singleLine(block.joined(separator: " "))
            block = []
            guard !text.isEmpty, TextUtils.hasLetterOrDigit(text) else { return }
            paragraphs.append(ParsedParagraph(text: text, chapter: chapter))
            sawText = true
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                inFence.toggle()
                continue
            }
            if inFence {
                // Code keeps its lines; each fenced block is one paragraph.
                block.append(line)
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let level = headingLevel(trimmed) {
                flush()
                let text = inlineText(String(trimmed.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                if level == 1, title == nil, !sawText, paragraphs.isEmpty {
                    title = text
                } else if level <= 3, !text.isEmpty {
                    chapter = text
                }
                continue
            }
            if trimmed.allSatisfy({ "-*_ ".contains($0) }) && trimmed.filter({ $0 != " " }).count >= 3 {
                flush() // Thematic break.
                continue
            }
            if let item = listItemText(trimmed) {
                flush()
                block.append(inlineText(item))
                flush()
                continue
            }
            var content = trimmed
            while content.hasPrefix(">") {
                content = String(content.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            block.append(inlineText(content))
        }
        flush()
        return ParsedBook(
            title: title ?? fallbackTitle,
            author: author ?? "Unknown author",
            format: .markdown,
            paragraphs: paragraphs,
            passagesOnly: false,
            note: nil
        )
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " ? hashes : nil
    }

    private static func listItemText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        // "1. " or "1) "
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return String(rest.dropFirst(2)) }
        }
        return nil
    }

    /// Removes inline markup: images, links (keeps their text), emphasis, code and HTML tags.
    static func inlineText(_ text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            (#"!\[[^\]]*\]\([^)]*\)"#, ""),          // images
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),       // links
            (#"\[([^\]]+)\]\[[^\]]*\]"#, "$1"),      // reference links
            (#"<[^>]+>"#, ""),                       // inline HTML
            (#"(?<!\\)(\*\*|__)(.+?)(?<!\\)\1"#, "$2"),      // strong
            (#"(?<![\w*\\])\*(?![\s*])(.+?)(?<![\s\\])\*(?![\w*])"#, "$1"), // emphasis
            (#"(?<![\w\\])_(?![\s_])(.+?)(?<![\s\\])_(?!\w)"#, "$1"),
            (#"(?<!\\)~~(.+?)~~"#, "$1"),
            (#"(?<!\\)`([^`]*)`"#, "$1"),
            (#"\\([\\`*_{}\[\]()#+\-.!>])"#, "$1"),  // escapes
        ]
        for (pattern, template) in replacements {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return HTMLEntities.decode(result)
    }

    // MARK: HTML

    /// The first capture group of `pattern` (case-insensitive), or nil.
    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func parseHTML(_ html: String, fallbackTitle: String) -> ParsedBook {
        func clean(_ value: String?) -> String? {
            guard let value else { return nil }
            let text = TextUtils.singleLine(HTMLEntities.decode(value.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)))
            return text.isEmpty ? nil : text
        }
        let title = clean(firstCapture(#"<title[^>]*>([\s\S]*?)</title>"#, in: html))
        let author = clean(firstCapture(#"<meta[^>]+name\s*=\s*["']author["'][^>]*content\s*=\s*["']([^"']*)["']"#, in: html))
            ?? clean(firstCapture(#"<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*name\s*=\s*["']author["']"#, in: html))
        var paragraphs: [ParsedParagraph] = []
        var chapter = ""
        for block in HTMLTextExtractor.blocks(from: html) {
            guard TextUtils.hasLetterOrDigit(block.text) else { continue }
            if let level = block.headingLevel {
                if level <= 3 { chapter = TextUtils.singleLine(block.text) }
                continue
            }
            paragraphs.append(ParsedParagraph(text: block.text, chapter: chapter))
        }
        return ParsedBook(
            title: title ?? fallbackTitle,
            author: author ?? "Unknown author",
            format: .html,
            paragraphs: paragraphs,
            passagesOnly: false,
            note: nil
        )
    }
}
