import Foundation
import UniformTypeIdentifiers

/// How the feed cuts a book into posts.
enum PostStyle: String, CaseIterable, Identifiable, Sendable {
    /// One post is exactly one paragraph of the book.
    case paragraph
    /// One post is about 80 words, cut on sentence boundaries.
    case passage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paragraph: return "Paragraphs"
        case .passage: return "Passages"
        }
    }

    /// Integer stored in SwiftData. Integers keep predicates and key arithmetic simple.
    var storageValue: Int { self == .paragraph ? 0 : 1 }

    init(storageValue: Int) {
        self = storageValue == 0 ? .paragraph : .passage
    }
}

enum BookFormat: String, CaseIterable, Sendable {
    case epub
    case pdf
    /// Plain text, also used for pasted text.
    case text
    case markdown
    case html
    case rtf

    /// The short badge in the Library.
    var label: String {
        switch self {
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        case .text: return "TXT"
        case .markdown: return "MD"
        case .html: return "HTML"
        case .rtf: return "RTF"
        }
    }

    /// Markdown files; iOS has no built-in type for them.
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)

    /// File types offered in the Files picker and declared as document types in Info.plist.
    static let importableTypes: [UTType] = [.epub, .pdf, .plainText, markdownType, .html, .rtf]

    /// The format a file name suggests, for files whose first bytes do not tell.
    static func fromExtension(_ fileExtension: String) -> BookFormat? {
        switch fileExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        case "txt", "text": return .text
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "html", "htm", "xhtml": return .html
        case "rtf": return .rtf
        default: return nil
        }
    }
}

enum MarkKind: String, CaseIterable, Sendable {
    /// Old: likes were removed. Stores and backups can still hold them; they become bookmarks
    /// (`LibraryStore.convertLikesToBookmarks`, `LibraryStore.addMark`).
    case like
    case bookmark
    /// A range the reader marked, from a selection in the reader or a whole post.
    case highlight
}

/// Bookmark colours. A new bookmark has no highlight (the default); the reader can pick a
/// colour, and the bookmark then highlights its text in it.
enum MarkColor: String, CaseIterable, Identifiable, Sendable {
    /// Not named `none`, so it never mixes with `Optional.none`.
    case noHighlight = "none"
    case yellow
    case red
    case blue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yellow: return String(localized: "Yellow")
        case .red: return String(localized: "Red")
        case .blue: return String(localized: "Blue")
        case .noHighlight: return String(localized: "No highlight")
        }
    }

    var highlightsText: Bool { self != .noHighlight }
}

/// A coloured range of a text (UTF-16), for bookmark highlights.
struct MarkerRange: Equatable, Sendable {
    let range: NSRange
    let color: MarkColor
}

/// Composite integer keys for segments. Both keys are unique attributes, so SQLite keeps an
/// index on each and lookups by (book, style, index) or (book, style, offset) are index range scans.
///
/// Layout: `ordinal << 33 | style << 32 | value`, where `value` is the segment index or the
/// segment's start offset (always below 2^32).
enum SegmentKey {
    static let valueLimit: Int64 = 1 << 32

    static func make(ordinal: Int, style: PostStyle, value: Int) -> Int64 {
        let clamped = min(max(Int64(value), 0), valueLimit - 1)
        return (Int64(ordinal) << 33) | (Int64(style.storageValue) << 32) | clamped
    }

    static func lowerBound(ordinal: Int, style: PostStyle) -> Int64 {
        make(ordinal: ordinal, style: style, value: 0)
    }

    static func upperBound(ordinal: Int, style: PostStyle) -> Int64 {
        lowerBound(ordinal: ordinal, style: style) + valueLimit
    }
}
