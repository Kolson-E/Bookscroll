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

enum BookFormat: String, Sendable {
    case epub
    case pdf

    var label: String { rawValue.uppercased() }

    /// File types offered in the Files picker and declared as document types in Info.plist.
    static let importableTypes: [UTType] = [.epub, .pdf]
}

enum MarkKind: String, CaseIterable, Sendable {
    case like
    case bookmark
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
