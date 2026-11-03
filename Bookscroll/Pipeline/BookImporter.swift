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

enum BookWriter {
    static let saveInterval = 4000

    static func write(
        parsed: ParsedBook,
        segmented: SegmentedBook,
        into context: ModelContext,
        progress: (Double) -> Void = { _ in }
    ) throws -> UUID {
        var lastBook = FetchDescriptor<Book>(sortBy: [SortDescriptor(\.ordinal, order: .reverse)])
        lastBook.fetchLimit = 1
        let ordinal = ((try context.fetch(lastBook)).first?.ordinal ?? 0) + 1

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
        context.insert(book)

        do {
            let drafts = segmented.paragraphs + segmented.passages
            for (n, draft) in drafts.enumerated() {
                let segment = Segment(bookID: bookID, ordinal: ordinal, draft: draft)
                context.insert(segment)
                segment.book = book
                if (n + 1) % saveInterval == 0 {
                    try context.save()
                    progress(Double(n + 1) / Double(drafts.count))
                }
            }
            try context.save()
            progress(1)
        } catch {
            context.rollback()
            try? context.delete(model: Segment.self, where: #Predicate { $0.bookID == bookID })
            try? context.delete(model: Book.self, where: #Predicate { $0.id == bookID })
            try? context.save()
            throw BookImportError.unreadable("The book could not be saved (\(error.localizedDescription)).")
        }
        return bookID
    }
}
