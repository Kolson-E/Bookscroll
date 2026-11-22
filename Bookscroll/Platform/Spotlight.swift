import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// One item in the system search (Spotlight): a book, or a highlight.
struct SpotlightEntry: Equatable, Sendable {
    let link: AppLink
    let title: String
    let detail: String
    let keywords: [String]
    let thumbnail: URL?

    var id: String { link.spotlightID ?? "" }
}

enum SpotlightContent {
    struct BookFacts: Sendable {
        let id: UUID
        let title: String
        let author: String
        let percent: Int
        let isFinished: Bool
        let thumbnail: URL?
    }

    struct HighlightFacts: Sendable {
        let id: UUID
        let bookTitle: String
        let bookAuthor: String
        let text: String
    }

    /// Highlights indexed at most (newest first).
    static let highlightLimit = 500
    /// Characters of a highlight shown in the result.
    static let highlightLength = 300

    static func entries(books: [BookFacts], highlights: [HighlightFacts]) -> [SpotlightEntry] {
        let bookEntries = books.map { book in
            SpotlightEntry(
                link: .book(book.id),
                title: book.title,
                detail: "\(book.author) \u{00B7} " + (book.isFinished ? "Finished" : "\(book.percent)% read"),
                keywords: [book.author, "book"],
                thumbnail: book.thumbnail
            )
        }
        let highlightEntries = highlights.prefix(highlightLimit).map { highlight in
            SpotlightEntry(
                link: .highlight(highlight.id),
                title: "Highlight in \(highlight.bookTitle)",
                detail: String(highlight.text.prefix(highlightLength)),
                keywords: [highlight.bookTitle, highlight.bookAuthor, "highlight"],
                thumbnail: nil
            )
        }
        return bookEntries + highlightEntries
    }
}

/// Keeps the Spotlight index equal to the library. Each update replaces all of the app's items.
@MainActor
final class SpotlightIndexer {
    nonisolated static let domain = "library"

    private let index: CSSearchableIndex?
    private var indexed: [SpotlightEntry]?

    /// `enabled` false indexes nothing (tests).
    init(enabled: Bool) {
        index = enabled && CSSearchableIndex.isIndexingAvailable() ? CSSearchableIndex.default() : nil
    }

    func update(_ entries: [SpotlightEntry]) {
        guard let index, entries != indexed else { return }
        indexed = entries
        Self.replace(with: entries.map(Self.item), in: index)
    }

    /// Not on the main actor: the index calls back on its own queue.
    nonisolated private static func replace(with items: [CSSearchableItem], in index: CSSearchableIndex) {
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            guard !items.isEmpty else { return }
            index.indexSearchableItems(items) { _ in }
        }
    }

    nonisolated static func item(_ entry: SpotlightEntry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = entry.title
        attributes.contentDescription = entry.detail
        attributes.keywords = entry.keywords
        attributes.thumbnailURL = entry.thumbnail
        return CSSearchableItem(uniqueIdentifier: entry.id, domainIdentifier: domain, attributeSet: attributes)
    }
}
