import Foundation
import NaturalLanguage
import SwiftData

/// One chapter of a book: its label and where it starts.
struct ChapterEntry: Codable, Equatable, Hashable, Sendable {
    let title: String
    /// First paragraph (Paragraphs style index).
    let index: Int
    let charStart: Int
}

/// Values computed from a book's text once: the automatic word limit, the chapter table and
/// the language.
/// The importer computes them; `DerivedDataBackfill` computes them for books from before.
enum DerivedData {
    /// Raise this when the computation changes; older books are then computed again.
    /// 2 added the language.
    static let currentVersion = 2
    /// The automatic limit fits this share of a book's paragraphs in one post.
    static let coverage = 0.95
    /// Very short paragraphs (dialogue) would give a tiny limit; posts never split below this.
    static let minimumWordLimit = 40
    /// Characters of text the language is detected from.
    static let languageSampleLength = 6000

    /// Collects paragraphs in book order, in any number of batches.
    struct Builder {
        private(set) var wordCounts: [Int] = []
        private(set) var chapters: [ChapterEntry] = []
        private var lastChapter: String?
        private var sample = ""

        mutating func add(index: Int, charStart: Int, chapter: String, text: String) {
            wordCounts.append(TextUtils.wordCount(text))
            if sample.count < DerivedData.languageSampleLength {
                sample += text + "\n"
            }
            if chapter != lastChapter {
                if !chapter.isEmpty {
                    chapters.append(ChapterEntry(title: chapter, index: index, charStart: charStart))
                }
                lastChapter = chapter
            }
        }

        var wordLimit: Int { DerivedData.wordLimit(wordCounts: wordCounts) }

        var language: String? { DerivedData.language(of: sample) }
    }

    /// The dominant language as a BCP 47 code ("en", "de", "zh-Hans"), nil when unsure.
    static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage, language != .undetermined else { return nil }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        return confidence >= 0.5 ? language.rawValue : nil
    }

    /// The smallest length that fits `coverage` of the paragraphs, at least `minimumWordLimit`.
    static func wordLimit(wordCounts: [Int]) -> Int {
        guard !wordCounts.isEmpty else { return minimumWordLimit }
        let sorted = wordCounts.sorted()
        let position = Int((Double(sorted.count) * coverage).rounded(.up)) - 1
        return max(minimumWordLimit, sorted[min(max(position, 0), sorted.count - 1)])
    }

    static func encode(_ chapters: [ChapterEntry]) -> Data? {
        try? JSONEncoder().encode(chapters)
    }

    static func decode(_ data: Data?) -> [ChapterEntry] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([ChapterEntry].self, from: data)) ?? []
    }

    static func apply(_ builder: Builder, to book: Book) {
        book.autoWordLimit = builder.wordLimit
        book.chapterTable = encode(builder.chapters)
        book.language = builder.language
        book.derivedVersion = currentVersion
    }
}

/// Computes the derived values of books imported before they existed. Reads off the main
/// thread in bounded batches; the caller writes the results on its own context, so the
/// reading position (saved on the main context) is never overwritten.
enum DerivedDataBackfill {
    struct Result: Sendable {
        let bookID: UUID
        let wordLimit: Int
        let chapterTable: Data?
        var language: String? = nil
    }

    static func booksNeedingWork(in context: ModelContext) throws -> [FeedBook] {
        let version = DerivedData.currentVersion
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.deletionPending == false && $0.derivedVersion < version })
        return try context.fetch(descriptor).map(FeedBook.init)
    }

    static func compute(container: ModelContainer, batchSize: Int = 2000) throws -> [Result] {
        let context = ModelContext(container)
        var results: [Result] = []
        for book in try booksNeedingWork(in: context) {
            var builder = DerivedData.Builder()
            var next = 0
            while true {
                let lower = SegmentKey.make(ordinal: book.ordinal, style: .paragraph, value: next)
                let upper = SegmentKey.upperBound(ordinal: book.ordinal, style: .paragraph)
                var descriptor = FetchDescriptor<Segment>(
                    predicate: #Predicate { $0.indexKey >= lower && $0.indexKey < upper },
                    sortBy: [SortDescriptor(\.indexKey)]
                )
                descriptor.fetchLimit = batchSize
                let batch = try context.fetch(descriptor)
                for segment in batch {
                    builder.add(index: segment.index, charStart: segment.charStart, chapter: segment.chapter, text: segment.text)
                }
                guard batch.count == batchSize, let last = batch.last else { break }
                next = last.index + 1
            }
            results.append(Result(bookID: book.id, wordLimit: builder.wordLimit, chapterTable: DerivedData.encode(builder.chapters), language: builder.language))
        }
        return results
    }
}
