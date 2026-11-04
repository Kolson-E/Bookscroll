import Foundation
import SwiftData

/// A place in a book's text that survives a new version of the text: the offset, the length
/// of the whole text, and the words that start there.
struct TextAnchor: Codable, Equatable, Sendable {
    /// UTF-16 offset into the book's normalized text.
    var offset: Int
    /// Length of the whole text when the anchor was made.
    var total: Int
    /// Up to `TextAnchoring.length` UTF-16 units of text from `offset`.
    var text: String
}

enum TextAnchoring {
    /// Anchor text length, in UTF-16 units: long enough to be unique in a book, short enough
    /// to survive small edits nearby.
    static let length = 48

    static func anchor(at offset: Int, in text: NSString) -> TextAnchor {
        let start = min(max(0, offset), text.length)
        let range = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: min(length, text.length - start)))
        // Inside a character made of two UTF-16 units, the anchor starts at the character.
        return TextAnchor(offset: range.location, total: text.length, text: text.substring(with: range))
    }

    /// Where `anchor` is in `text`:
    /// 1. the same offset, when the anchor text is still there (the same text);
    /// 2. else the place of the anchor text nearest to the same fraction of the book;
    /// 3. else a shorter start of the anchor text (16 units), the same way;
    /// 4. else the same fraction of the book.
    static func locate(_ anchor: TextAnchor, in text: NSString) -> Int {
        guard text.length > 0 else { return 0 }
        let anchorText = anchor.text as NSString
        if anchorText.length > 0, anchor.offset + anchorText.length <= text.length,
           text.substring(with: NSRange(location: anchor.offset, length: anchorText.length)) == anchor.text {
            return anchor.offset
        }
        let fraction = anchor.total > 0 ? Double(anchor.offset) / Double(anchor.total) : 0
        let expected = Int((fraction * Double(text.length)).rounded())
        for probe in [anchor.text, anchorText.length > 16 ? anchorText.substring(to: 16) : nil] {
            guard let probe, (probe as NSString).length >= 8,
                  let found = nearestOccurrence(of: probe, in: text, to: expected) else { continue }
            return found
        }
        return min(max(0, expected), text.length)
    }

    private static func nearestOccurrence(of needle: String, in text: NSString, to expected: Int) -> Int? {
        var best: Int?
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: needle, options: [.literal], range: searchRange)
            guard found.location != NSNotFound else { break }
            if best.map({ abs(found.location - expected) < abs($0 - expected) }) ?? true {
                best = found.location
            }
            let next = found.location + 1
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return best
    }
}

/// A mark (like, bookmark, highlight) as text, so it can be put back on another version.
struct MarkState: Codable, Equatable, Sendable {
    var kind: String
    var start: TextAnchor
    var length: Int
    var createdAt: Date
}

/// What the reader has done with one book: place, finish, Mix settings, details, photo and
/// marks. Used to replace a book's file and for backups.
struct BookState: Codable, Equatable, Sendable {
    var title: String
    var author: String
    var format: String
    var totalCharacters: Int
    var position: TextAnchor
    var finishedAt: Date?
    var lastReadAt: Date?
    var addedAt: Date
    var hiddenFromMix: Bool
    var snoozedUntil: Date?
    var feedWeight: Double
    var showsCover: Bool
    /// The reader's own avatar photo (JPEG), if any.
    var photo: Data?
    var marks: [MarkState]
}

enum ReadingStateIO {
    /// The book's normalized text: its paragraphs joined by a blank line. Offsets everywhere in
    /// the app refer to this text.
    static func fullText(of book: Book, in context: ModelContext) throws -> NSString {
        let lower = SegmentKey.lowerBound(ordinal: book.ordinal, style: .paragraph)
        let upper = SegmentKey.upperBound(ordinal: book.ordinal, style: .paragraph)
        let descriptor = FetchDescriptor<Segment>(
            predicate: #Predicate { $0.indexKey >= lower && $0.indexKey < upper },
            sortBy: [SortDescriptor(\.indexKey)]
        )
        let text = try context.fetch(descriptor).map(\.text).joined(separator: Segmenter.separator)
        return text as NSString
    }

    static func capture(bookID: UUID, in context: ModelContext, photoFolder: URL = CoverStore.directory) throws -> BookState? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookID })
        descriptor.fetchLimit = 1
        guard let book = try context.fetch(descriptor).first else { return nil }
        let text = try fullText(of: book, in: context)
        let markDescriptor = FetchDescriptor<Mark>(
            predicate: #Predicate { $0.bookID == bookID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let marks = try context.fetch(markDescriptor).map { mark in
            MarkState(
                kind: mark.kindRaw,
                start: TextAnchoring.anchor(at: mark.charStart, in: text),
                length: max(0, mark.charEnd - mark.charStart),
                createdAt: mark.createdAt
            )
        }
        let photoURL = CoverStore.url(bookID: bookID, photo: true, in: photoFolder)
        return BookState(
            title: book.title,
            author: book.author,
            format: book.formatRaw,
            totalCharacters: book.totalCharacters,
            position: TextAnchoring.anchor(at: book.positionOffset, in: text),
            finishedAt: book.finishedAt,
            lastReadAt: book.lastReadAt,
            addedAt: book.addedAt,
            hiddenFromMix: book.hiddenFromMix,
            snoozedUntil: book.snoozedUntil,
            feedWeight: book.feedWeight,
            showsCover: book.showsCover,
            photo: try? Data(contentsOf: photoURL),
            marks: marks
        )
    }

    struct ApplyOptions: OptionSet, Sendable {
        let rawValue: Int
        /// Also the title, author and date added (a replaced file keeps the book's details).
        static let details = ApplyOptions(rawValue: 1)
    }

    /// A state placed on one book's text: offsets in that text.
    struct Resolved: Equatable, Sendable {
        struct ResolvedMark: Equatable, Sendable {
            var kind: MarkKind
            var start: Int
            var end: Int
            var createdAt: Date
        }

        var position: Int
        var marks: [ResolvedMark]
    }

    /// Places the saved position and marks on `text`. Pure; runs anywhere.
    static func resolve(_ state: BookState, in text: NSString) -> Resolved {
        let total = text.length
        let position = min(TextAnchoring.locate(state.position, in: text), max(0, total - 1))
        let marks: [Resolved.ResolvedMark] = total == 0 ? [] : state.marks.compactMap { saved in
            guard let kind = MarkKind(rawValue: saved.kind) else { return nil }
            let start = min(TextAnchoring.locate(saved.start, in: text), total - 1)
            let end = min(start + max(1, saved.length), total)
            return Resolved.ResolvedMark(kind: kind, start: start, end: end, createdAt: saved.createdAt)
        }
        return Resolved(position: position, marks: marks)
    }

    /// Writes a resolved state to `book`. Marks the book already has (same kind and range)
    /// are not added twice. Saves the context.
    static func write(
        _ state: BookState,
        resolved: Resolved,
        to book: Book,
        in context: ModelContext,
        options: ApplyOptions = [],
        photoFolder: URL = CoverStore.directory
    ) throws {
        let bookID = book.id
        book.positionOffset = resolved.position
        book.finishedAt = state.finishedAt
        book.lastReadAt = state.lastReadAt
        book.hiddenFromMix = state.hiddenFromMix
        book.snoozedUntil = state.snoozedUntil
        book.feedWeight = state.feedWeight
        book.showsCover = state.showsCover
        if options.contains(.details) {
            book.title = state.title
            book.author = state.author
            book.addedAt = state.addedAt
        }
        let markDescriptor = FetchDescriptor<Mark>(predicate: #Predicate { $0.bookID == bookID })
        var existing = Set(try context.fetch(markDescriptor).map { "\($0.kindRaw)|\($0.charStart)|\($0.charEnd)" })
        for saved in resolved.marks {
            guard existing.insert("\(saved.kind.rawValue)|\(saved.start)|\(saved.end)").inserted else { continue }
            let mark = Mark(bookID: bookID, kind: saved.kind, charStart: saved.start, charEnd: saved.end, createdAt: saved.createdAt)
            context.insert(mark)
            mark.book = book
        }
        try context.save()
        if let photo = state.photo {
            _ = CoverStore.save(photo, bookID: bookID, photo: true, in: photoFolder)
        }
    }

    /// Resolves and writes in one context (a book this context made, such as a new version).
    static func apply(
        _ state: BookState,
        to bookID: UUID,
        in context: ModelContext,
        options: ApplyOptions = [],
        photoFolder: URL = CoverStore.directory
    ) throws {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == bookID })
        descriptor.fetchLimit = 1
        guard let book = try context.fetch(descriptor).first else { return }
        let resolved = resolve(state, in: try fullText(of: book, in: context))
        try write(state, resolved: resolved, to: book, in: context, options: options, photoFolder: photoFolder)
    }
}
