import Foundation

/// The values the Library sorts and filters on. `Book` has them; tests use plain structs.
protocol LibraryArrangeable {
    var id: UUID { get }
    var title: String { get }
    var author: String { get }
    var addedAt: Date { get }
    var lastReadAt: Date? { get }
    var finishedAt: Date? { get }
    var positionOffset: Int { get }
    var progress: Double { get }
    var hiddenFromMix: Bool { get }
    var format: BookFormat { get }
}

extension Book: LibraryArrangeable {}

/// How the Library lists books.
enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyRead
    case recentlyAdded
    case title
    case author
    case progress

    var id: Self { self }

    var title: String {
        switch self {
        case .recentlyRead: return "Recently read"
        case .recentlyAdded: return "Recently added"
        case .title: return "Title"
        case .author: return "Author"
        case .progress: return "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .recentlyRead: return "clock"
        case .recentlyAdded: return "calendar"
        case .title: return "textformat"
        case .author: return "person"
        case .progress: return "chart.bar"
        }
    }
}

/// Which books the Library shows, by reading state.
enum LibraryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case reading
    case notStarted
    case finished
    case hidden

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All books"
        case .reading: return "Reading"
        case .notStarted: return "Not started"
        case .finished: return "Finished"
        case .hidden: return "Hidden from Mix"
        }
    }

    func includes(_ book: some LibraryArrangeable) -> Bool {
        switch self {
        case .all: return true
        case .reading: return book.finishedAt == nil && book.positionOffset > 0
        case .notStarted: return book.finishedAt == nil && book.positionOffset == 0
        case .finished: return book.finishedAt != nil
        case .hidden: return book.hiddenFromMix
        }
    }
}

/// Which books the Library shows, by file format.
enum LibraryFormatFilter: String, CaseIterable, Identifiable {
    case all
    case epub
    case pdf

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All formats"
        case .epub: return "EPUB"
        case .pdf: return "PDF"
        }
    }

    func includes(_ book: some LibraryArrangeable) -> Bool {
        switch self {
        case .all: return true
        case .epub: return book.format == .epub
        case .pdf: return book.format == .pdf
        }
    }
}

enum LibraryArrangement {
    /// Filters and sorts. Every order is total (ties fall back to title, then id), so the list
    /// never reorders between redraws.
    static func arrange<B: LibraryArrangeable>(
        _ books: [B],
        sort: LibrarySort,
        status: LibraryStatusFilter = .all,
        format: LibraryFormatFilter = .all
    ) -> [B] {
        let kept = books.filter { status.includes($0) && format.includes($0) }
        // Keys are computed once per book, not once per comparison.
        let keyed = kept.map { (book: $0, title: titleKey($0.title), author: authorKey($0.author)) }
        let sorted = keyed.sorted { a, b in
            switch sort {
            case .recentlyRead:
                // Books never opened go after the ones read, newest import first.
                let left = a.book.lastReadAt ?? .distantPast
                let right = b.book.lastReadAt ?? .distantPast
                if left != right { return left > right }
                if a.book.addedAt != b.book.addedAt { return a.book.addedAt > b.book.addedAt }
            case .recentlyAdded:
                if a.book.addedAt != b.book.addedAt { return a.book.addedAt > b.book.addedAt }
            case .title:
                break
            case .author:
                let order = a.author.localizedStandardCompare(b.author)
                if order != .orderedSame { return order == .orderedAscending }
            case .progress:
                // Finished books count as complete wherever their position is.
                let left = a.book.finishedAt == nil ? a.book.progress : 1.0001
                let right = b.book.finishedAt == nil ? b.book.progress : 1.0001
                if left != right { return left > right }
            }
            let order = a.title.localizedStandardCompare(b.title)
            if order != .orderedSame { return order == .orderedAscending }
            return a.book.id.uuidString < b.book.id.uuidString
        }
        return sorted.map(\.book)
    }

    /// The title as it files in a library: a leading "The", "A" or "An" is ignored.
    static func titleKey(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["the ", "a ", "an "] where trimmed.lowercased().hasPrefix(article) {
            let rest = trimmed.dropFirst(article.count).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return rest }
        }
        return trimmed
    }

    /// The author as it files: surname first. "Jane Austen" files as "Austen Jane";
    /// "Austen, Jane" is already in that form; for several authors ("A, B" as the importer
    /// joins them, "A and B", "A & B", "A; B") the first one counts; "Jr." and similar
    /// suffixes are skipped.
    static func authorKey(_ author: String) -> String {
        var first = author.trimmingCharacters(in: .whitespacesAndNewlines)
        for separator in [";", " & ", " and ", " und ", " et "] {
            if let range = first.range(of: separator, options: .caseInsensitive) {
                first = String(first[..<range.lowerBound])
            }
        }
        first = first.trimmingCharacters(in: .whitespaces)
        if first.contains(",") {
            let parts = first.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let head = parts[0]
            let headWords = head.split(separator: " ")
            let tail = parts.count > 1 ? parts[1] : ""
            if isSuffix(tail) {
                // "Martin Luther King, Jr."
                first = head
            } else if headWords.count == 1 || headWords.first?.first?.isLowercase == true {
                // "Austen, Jane", "van Gogh, Vincent": already surname first.
                return tail.isEmpty ? head : head + " " + tail
            } else {
                // "Ada Example, Ben Sample": a list of names.
                first = head
            }
        }
        var words = first.split(separator: " ").map(String.init)
        while words.count > 1, let last = words.last, isSuffix(last) { words.removeLast() }
        guard words.count > 1, let surname = words.last else { return words.first ?? first }
        return ([surname] + words.dropLast()).joined(separator: " ")
    }

    private static func isSuffix(_ word: String) -> Bool {
        let bare = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,"))
        return ["jr", "sr", "ii", "iii", "iv", "phd", "md"].contains(bare)
    }
}
