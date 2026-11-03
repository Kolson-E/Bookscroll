import Foundation
import SwiftData

@Model
final class Book {
    @Attribute(.unique) var id: UUID
    /// Small integer assigned at import. It prefixes the segment keys of this book.
    var ordinal: Int
    var title: String
    var author: String
    var formatRaw: String
    var addedAt: Date
    /// Length of the normalized text in UTF-16 code units. All offsets use the same unit.
    var totalCharacters: Int
    /// Reading position as an offset into the normalized text (not a post index).
    var positionOffset: Int
    /// True when paragraph detection failed (PDF paragraphs average over 300 words)
    /// and the book always shows Passages style.
    var passagesOnly: Bool
    var paragraphSegmentCount: Int
    var passageSegmentCount: Int
    var importNote: String?
    @Relationship(deleteRule: .cascade, inverse: \Segment.book) var segments: [Segment]? = []
    @Relationship(deleteRule: .cascade, inverse: \Mark.book) var marks: [Mark]? = []

    init(
        id: UUID = UUID(),
        ordinal: Int,
        title: String,
        author: String,
        format: BookFormat,
        addedAt: Date = .now,
        totalCharacters: Int,
        positionOffset: Int = 0,
        passagesOnly: Bool,
        paragraphSegmentCount: Int,
        passageSegmentCount: Int,
        importNote: String?
    ) {
        self.id = id
        self.ordinal = ordinal
        self.title = title
        self.author = author
        self.formatRaw = format.rawValue
        self.addedAt = addedAt
        self.totalCharacters = totalCharacters
        self.positionOffset = positionOffset
        self.passagesOnly = passagesOnly
        self.paragraphSegmentCount = paragraphSegmentCount
        self.passageSegmentCount = passageSegmentCount
        self.importNote = importNote
    }

    var format: BookFormat { BookFormat(rawValue: formatRaw) ?? .epub }

    var progress: Double {
        guard totalCharacters > 0 else { return 0 }
        return min(1, max(0, Double(positionOffset) / Double(totalCharacters)))
    }
}

@Model
final class Segment {
    var bookID: UUID
    var styleRaw: Int
    var index: Int
    var charStart: Int
    var charEnd: Int
    var chapter: String
    var text: String
    @Attribute(.unique) var indexKey: Int64
    @Attribute(.unique) var offsetKey: Int64
    var book: Book?

    init(bookID: UUID, ordinal: Int, draft: SegmentDraft) {
        self.bookID = bookID
        self.styleRaw = draft.style.storageValue
        self.index = draft.index
        self.charStart = draft.charStart
        self.charEnd = draft.charEnd
        self.chapter = draft.chapter
        self.text = draft.text
        self.indexKey = SegmentKey.make(ordinal: ordinal, style: draft.style, value: draft.index)
        self.offsetKey = SegmentKey.make(ordinal: ordinal, style: draft.style, value: draft.charStart)
    }

    var style: PostStyle { PostStyle(storageValue: styleRaw) }
}

@Model
final class Mark {
    @Attribute(.unique) var id: UUID
    var bookID: UUID
    var kindRaw: String
    var charStart: Int
    var charEnd: Int
    var createdAt: Date
    var book: Book?

    init(id: UUID = UUID(), bookID: UUID, kind: MarkKind, charStart: Int, charEnd: Int, createdAt: Date = .now) {
        self.id = id
        self.bookID = bookID
        self.kindRaw = kind.rawValue
        self.charStart = charStart
        self.charEnd = charEnd
        self.createdAt = createdAt
    }

    var kind: MarkKind { MarkKind(rawValue: kindRaw) ?? .like }
}
