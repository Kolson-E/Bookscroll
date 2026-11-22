import Foundation
import SwiftData

/// Parses a file and stores the book with its segments. Runs off the main thread.
enum BookImporter {
    /// Parses a book file. EPUB, PDF and RTF are known by their first bytes, so a wrong file
    /// extension does not matter; text formats are known by their extension.
    static func parse(url: URL, progress: (Double) -> Void) throws -> ParsedBook {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let format = try detectFormat(url)
        switch format {
        case .epub:
            return try EPUBBookParser.parse(url: url, fallbackTitle: fallbackTitle, progress: progress)
        case .pdf:
            return try PDFBookParser.parse(url: url, fallbackTitle: fallbackTitle, progress: progress)
        case .text, .markdown, .html, .rtf:
            progress(0)
            let parsed = try TextBookParser.parse(url: url, format: format, fallbackTitle: fallbackTitle)
            progress(1)
            return parsed
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
        if head.starts(with: Data("{\\rtf".utf8)) { return .rtf }
        switch BookFormat.fromExtension(url.pathExtension) {
        case .epub: throw BookImportError.unreadable("It is not a valid EPUB (ZIP) archive.")
        case .pdf: throw BookImportError.unreadable("It is not a valid PDF.")
        case .rtf: throw BookImportError.unreadable("It is not a valid RTF document.")
        case let format?:
            guard TextBookParser.decode(head) != nil || head.isEmpty else {
                throw BookImportError.unreadable("It does not contain text.")
            }
            return format
        case nil:
            throw BookImportError.unsupportedFormat
        }
    }

    /// Full import: parse, segment, store. Returns the new book's id.
    /// `progress` is called with values from 0 to 1, on the calling thread.
    @discardableResult
    /// `replacing`: the book this file replaces. It does not count as a duplicate.
    static func importBook(
        at url: URL,
        into container: ModelContainer,
        replacing: UUID? = nil,
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
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return try store(parsed, source: (name: url.lastPathComponent, size: size), into: container, replacing: replacing, report: report)
    }

    /// Imports pasted text as a book. Returns the new book's id.
    @discardableResult
    static func importPasted(
        text: String,
        title: String,
        author: String,
        into container: ModelContainer,
        progress: @escaping (Double) -> Void = { _ in }
    ) throws -> UUID {
        let parsed = TextBookParser.parsePasted(text, title: title, author: author)
        return try store(parsed, source: nil, into: container, report: progress)
    }

    /// Segments and stores a parsed book, and saves its cover.
    private static func store(
        _ parsed: ParsedBook,
        source: (name: String, size: Int)?,
        into container: ModelContainer,
        replacing: UUID? = nil,
        report: @escaping (Double) -> Void
    ) throws -> UUID {
        let segmented = Segmenter.segment(parsed.paragraphs)
        guard !segmented.paragraphs.isEmpty else { throw BookImportError.noText }
        report(0.75)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let id = try BookWriter.write(
            parsed: parsed,
            segmented: segmented,
            into: context,
            source: source,
            replacing: replacing
        ) { report(0.75 + $0 * 0.25) }
        if let cover = parsed.cover {
            CoverStore.save(cover, bookID: id)
        }
        return id
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
        source: (name: String, size: Int)? = nil,
        replacing: UUID? = nil,
        progress: (Double) -> Void = { _ in }
    ) throws -> UUID {
        try rejectDuplicate(parsed: parsed, segmented: segmented, in: context, except: replacing)
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
        book.sourceFileName = source?.name
        book.sourceFileSize = source?.size ?? 0
        let bookID = book.id
        var derived = DerivedData.Builder()
        for draft in segmented.paragraphs {
            derived.add(index: draft.index, charStart: draft.charStart, chapter: draft.chapter, text: draft.text)
        }
        DerivedData.apply(derived, to: book)

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
    static func rejectDuplicate(parsed: ParsedBook, segmented: SegmentedBook, in context: ModelContext, except: UUID? = nil) throws {
        let title = parsed.title
        let author = parsed.author
        let total = segmented.totalCharacters
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate {
            $0.title == title && $0.author == author && $0.totalCharacters == total && $0.deletionPending == false
        })
        if try context.fetch(descriptor).contains(where: { $0.id != except }) {
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
