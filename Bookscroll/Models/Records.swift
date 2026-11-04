import Foundation

/// A paragraph produced by a parser, before normalization.
struct ParsedParagraph: Equatable, Sendable {
    var text: String
    var chapter: String
}

/// Output of a format parser (EPUB or PDF).
struct ParsedBook: Sendable {
    var title: String
    var author: String
    var format: BookFormat
    var paragraphs: [ParsedParagraph]
    /// Set when the parser could not find usable paragraph breaks.
    var passagesOnly: Bool
    var note: String?
    /// Cover image data as found in the file (EPUB cover image, first PDF page). Nil when none.
    var cover: Data? = nil
}

/// A segment computed at import, before it is stored.
struct SegmentDraft: Equatable, Sendable {
    var style: PostStyle
    var index: Int
    var charStart: Int
    var charEnd: Int
    var chapter: String
    var text: String
}

/// Value copy of a stored segment, used by the UI so views never hold SwiftData objects.
struct SegmentRecord: Equatable, Hashable, Sendable {
    let bookID: UUID
    let style: PostStyle
    let index: Int
    let charStart: Int
    let charEnd: Int
    let chapter: String
    let text: String

    /// End of the text itself: `charEnd` also covers the separator after it.
    var textEnd: Int { charStart + (text as NSString).length }

    init(bookID: UUID, style: PostStyle, index: Int, charStart: Int, charEnd: Int, chapter: String, text: String) {
        self.bookID = bookID
        self.style = style
        self.index = index
        self.charStart = charStart
        self.charEnd = charEnd
        self.chapter = chapter
        self.text = text
    }

    init(_ segment: Segment) {
        self.init(
            bookID: segment.bookID,
            style: segment.style,
            index: segment.index,
            charStart: segment.charStart,
            charEnd: segment.charEnd,
            chapter: segment.chapter,
            text: segment.text
        )
    }

    init(bookID: UUID, draft: SegmentDraft) {
        self.init(
            bookID: bookID,
            style: draft.style,
            index: draft.index,
            charStart: draft.charStart,
            charEnd: draft.charEnd,
            chapter: draft.chapter,
            text: draft.text
        )
    }

    func contains(offset: Int) -> Bool { charStart <= offset && offset < charEnd }
}

/// Value copy of a stored mark.
struct MarkRecord: Equatable, Identifiable, Sendable {
    let id: UUID
    let bookID: UUID
    let kind: MarkKind
    let charStart: Int
    let charEnd: Int
    let createdAt: Date

    init(id: UUID = UUID(), bookID: UUID, kind: MarkKind, charStart: Int, charEnd: Int, createdAt: Date = .now) {
        self.id = id
        self.bookID = bookID
        self.kind = kind
        self.charStart = charStart
        self.charEnd = charEnd
        self.createdAt = createdAt
    }

    init(_ mark: Mark) {
        self.init(
            id: mark.id,
            bookID: mark.bookID,
            kind: mark.kind,
            charStart: mark.charStart,
            charEnd: mark.charEnd,
            createdAt: mark.createdAt
        )
    }

    /// Half-open range overlap.
    func overlaps(start: Int, end: Int) -> Bool {
        charStart < end && start < charEnd
    }
}

/// Book summary used by the feed engine.
struct FeedBook: Equatable, Identifiable, Sendable {
    let id: UUID
    let ordinal: Int
    let title: String
    let author: String
    let totalCharacters: Int
    var positionOffset: Int
    let passagesOnly: Bool
    let paragraphCount: Int
    let passageCount: Int
    /// "Auto" word limit for this book; 0 until computed.
    var autoWordLimit: Int
    var hiddenFromMix: Bool
    var snoozedUntil: Date?
    var feedWeight: Double
    /// Set when the reader marked the book as finished. Finished books leave Mix.
    var finishedAt: Date?

    init(
        id: UUID,
        ordinal: Int,
        title: String,
        author: String,
        totalCharacters: Int,
        positionOffset: Int,
        passagesOnly: Bool,
        paragraphCount: Int,
        passageCount: Int,
        autoWordLimit: Int = 0,
        hiddenFromMix: Bool = false,
        snoozedUntil: Date? = nil,
        feedWeight: Double = 1,
        finishedAt: Date? = nil
    ) {
        self.finishedAt = finishedAt
        self.autoWordLimit = autoWordLimit
        self.hiddenFromMix = hiddenFromMix
        self.snoozedUntil = snoozedUntil
        self.feedWeight = feedWeight
        self.id = id
        self.ordinal = ordinal
        self.title = title
        self.author = author
        self.totalCharacters = totalCharacters
        self.positionOffset = positionOffset
        self.passagesOnly = passagesOnly
        self.paragraphCount = paragraphCount
        self.passageCount = passageCount
    }

    init(_ book: Book) {
        self.init(
            id: book.id,
            ordinal: book.ordinal,
            title: book.title,
            author: book.author,
            totalCharacters: book.totalCharacters,
            positionOffset: book.positionOffset,
            passagesOnly: book.passagesOnly,
            paragraphCount: book.paragraphSegmentCount,
            passageCount: book.passageSegmentCount,
            autoWordLimit: book.autoWordLimit,
            hiddenFromMix: book.hiddenFromMix,
            snoozedUntil: book.snoozedUntil,
            feedWeight: book.feedWeight,
            finishedAt: book.finishedAt
        )
    }

    var isFinished: Bool { finishedAt != nil }

    /// Mix leaves the book out (hidden, finished, or snoozed until after `now`).
    func isExcludedFromMix(now: Date) -> Bool {
        if hiddenFromMix || isFinished { return true }
        if let snoozedUntil, snoozedUntil > now { return true }
        return false
    }

    /// Books with forced passages always use Passages style.
    func effectiveStyle(_ style: PostStyle) -> PostStyle {
        passagesOnly ? .passage : style
    }

    func segmentCount(_ style: PostStyle) -> Int {
        style == .paragraph ? paragraphCount : passageCount
    }
}
