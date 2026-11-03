import Foundation
import SwiftData

/// Parses a file and stores the book with its segments. Runs off the main thread.
enum BookImporter {
    /// Parses an EPUB or PDF file. The format comes from the file's first bytes, so a wrong
    /// file extension does not matter.
    static func parse(url: URL, progress: (Double) -> Void) throws -> ParsedBook {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        switch try detectFormat(url) {
        case .epub:
            return try EPUBBookParser.parse(url: url, fallbackTitle: fallbackTitle, progress: progress)
        case .pdf:
            return try PDFBookParser.parse(url: url, fallbackTitle: fallbackTitle, progress: progress)
        }
    }

    static func detectFormat(_ url: URL) throws -> BookFormat {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw BookImportError.unreadable("The file could not be opened.")
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 1024)) ?? Data()
        if head.starts(with: [0x50, 0x4B]) { return .epub }
        if let range = head.range(of: Data("%PDF".utf8)), range.lowerBound < 1024 { return .pdf }
        switch url.pathExtension.lowercased() {
        case "epub": throw BookImportError.unreadable("It is not a valid EPUB (ZIP) archive.")
        case "pdf": throw BookImportError.unreadable("It is not a valid PDF.")
        default: throw BookImportError.unsupportedFormat
        }
    }

    /// Full import: parse, segment, store. Returns the new book's id.
    /// `progress` is called with values from 0 to 1, on the calling thread.
    @discardableResult
    static func importBook(
        at url: URL,
        into container: ModelContainer,
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> UUID {
        var lastReported = -1.0
        let report: (Double) -> Void = { value in
            if value - lastReported >= 0.01 || value >= 1 {
                lastReported = value
                progress(value)
            }
        }
        let parsed = try parse(url: url) { report($0 * 0.7) }
        let segmented = Segmenter.segment(parsed.paragraphs)
        guard !segmented.paragraphs.isEmpty else { throw BookImportError.noText }
        report(0.75)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try BookWriter.write(parsed: parsed, segmented: segmented, into: context) { report(0.75 + $0 * 0.25) }
    }
}

/// Stores a parsed book. All rows are written in one save, so an import is either complete
/// or absent: a crash or a failed save never leaves a partial book behind.
enum BookWriter {
    /// How often progress is reported while segments are inserted.
    static let progressInterval = 1000

    static func write(
        parsed: ParsedBook,
        segmented: SegmentedBook,
        into context: ModelContext,
        progress: (Double) -> Void = { _ in }
    ) throws -> UUID {
        try rejectDuplicate(parsed: parsed, segmented: segmented, in: context)
        let ordinal = try nextOrdinal(in: context)

        let book = Book(
            ordinal: ordinal,
            title: parsed.title,
            author: parsed.author,
            format: parsed.format,
            totalCharacters: segmented.totalCharacters,
            passagesOnly: parsed.passagesOnly,
            paragraphSegmentCount: segmented.paragraphs.count,
            passageSegmentCount: segmented.passages.count,
            importNote: parsed.note
        )
        let bookID = book.id

        do {
            context.insert(book)
            let drafts = segmented.paragraphs + segmented.passages
            var segments: [Segment] = []
            segments.reserveCapacity(drafts.count)
            for (n, draft) in drafts.enumerated() {
                let segment = Segment(bookID: bookID, ordinal: ordinal, draft: draft)
                context.insert(segment)
                segments.append(segment)
                if (n + 1) % progressInterval == 0 {
                    progress(0.8 * Double(n + 1) / Double(drafts.count))
                }
            }
            // One assignment sets the relationship for all segments. Setting `segment.book`
            // one by one grows the book's array on every call, which is quadratic.
            book.segments = segments
            progress(0.8)
            try context.save()
            progress(1)
        } catch {
            context.rollback()
            throw BookImportError.unreadable("The book could not be saved (\(error.localizedDescription)).")
        }
        return bookID
    }

    /// The same title, author and text length means the same book.
    static func rejectDuplicate(parsed: ParsedBook, segmented: SegmentedBook, in context: ModelContext) throws {
        let title = parsed.title
        let author = parsed.author
        let total = segmented.totalCharacters
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate {
            $0.title == title && $0.author == author && $0.totalCharacters == total && $0.deletionPending == false
        })
        descriptor.fetchLimit = 1
        if try context.fetchCount(descriptor) > 0 {
            throw BookImportError.duplicate(title)
        }
    }

    /// One more than the highest ordinal used by any book or segment. Segment keys carry the
    /// ordinal in their top bits, so leftover segments can never collide with a new book.
    static func nextOrdinal(in context: ModelContext) throws -> Int {
        var lastBook = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.ordinal, order: .reverse)])
        lastBook.fetchLimit = 1
        let bookOrdinal = try context.fetch(lastBook).first?.ordinal ?? 0
        var lastSegment = FetchDescriptor<Segment>(sortBy: [SortDescriptor(\.indexKey, order: .reverse)])
        lastSegment.fetchLimit = 1
        let segmentOrdinal = try context.fetch(lastSegment).first.map { Int($0.indexKey >> 33) } ?? 0
        return max(bookOrdinal, segmentOrdinal) + 1
    }
}
