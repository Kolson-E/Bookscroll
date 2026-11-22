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
    /// Set when the user deletes the book. The book is hidden at once and its rows are
    /// removed in the background; a deletion cut short (the app was closed) resumes at launch.
    var deletionPending: Bool = false

    // Version 2.
    /// Left out of Mix (still readable in One book mode).
    var hiddenFromMix: Bool = false
    /// Left out of Mix until this time.
    var snoozedUntil: Date? = nil
    /// How often Mix picks this book: 0.5 less, 1 normal, 2 more.
    var feedWeight: Double = 1
    /// Word limit that fits 95% of this book's paragraphs ("Auto" setting). 0 until computed.
    var autoWordLimit: Int = 0
    /// JSON list of `ChapterEntry`, in book order. Nil until computed.
    var chapterTable: Data? = nil
    /// Version of the values computed from the text (`DerivedData.currentVersion`).
    var derivedVersion: Int = 0

    // Version 3.
    /// Set when the reader marks the book as finished (Library). Finished books leave Mix.
    var finishedAt: Date? = nil
    /// Last time a post of this book was shown or the reader moved in it.
    var lastReadAt: Date? = nil
    /// BCP 47 language code detected from the text (for example "en", "de"). Nil until detected.
    var language: String? = nil
    /// Name of the imported file, for re-import and folder sync.
    var sourceFileName: String? = nil
    /// Size of the imported file in bytes; 0 when unknown.
    var sourceFileSize: Int = 0
    /// The avatar shows the book's cover (or the reader's photo) when true, the initial when false.
    var showsCover: Bool = true

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

/// A named list of books (Shelves tab). Books keep their place in the list.
@Model
final class Shelf {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    /// Position among the shelves.
    var sortIndex: Int
    var bookIDs: [UUID]

    init(id: UUID = UUID(), name: String, createdAt: Date = .now, sortIndex: Int, bookIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.bookIDs = bookIDs
    }
}
