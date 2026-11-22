import Foundation

/// How much space Bookscroll takes on the device, in total and per book.
///
/// The library database and the search index hold every book together, so a book's share of
/// them is estimated from its length: a book with a quarter of all characters gets a quarter
/// of each file. Its cover and photo are measured exactly. The shares add up to the totals.
struct StorageReport: Equatable, Sendable {
    struct BookUsage: Equatable, Identifiable, Sendable {
        let id: UUID
        let title: String
        let author: String
        let format: BookFormat
        /// Estimated bytes, cover and photo included.
        let bytes: Int64
    }

    /// The library database with its `-wal` and `-shm` files.
    var database: Int64
    var searchIndex: Int64
    var covers: Int64
    /// Largest first; ties by title.
    var books: [BookUsage]

    var total: Int64 { database + searchIndex + covers }

    static let empty = StorageReport(database: 0, searchIndex: 0, covers: 0, books: [])

    /// The facts about one book that the report needs.
    struct BookFacts: Sendable {
        let id: UUID
        let title: String
        let author: String
        let format: BookFormat
        let characters: Int
    }

    /// Where Bookscroll keeps its files. A nil URL (a store in memory) counts as 0 bytes.
    struct Locations: Sendable {
        var database: URL?
        var searchIndex: URL?
        var covers: URL
    }

    /// Measures the files. Runs file system calls; call it off the main thread.
    static func measure(books: [BookFacts], at locations: Locations) -> StorageReport {
        let database = locations.database.map(sqliteSize) ?? 0
        let searchIndex = locations.searchIndex.map(sqliteSize) ?? 0
        let covers = size(of: locations.covers)
        let totalCharacters = books.reduce(0) { $0 + max($1.characters, 0) }
        let shared = database + searchIndex
        var usages = books.map { book -> BookUsage in
            let share = totalCharacters > 0
                ? Int64((Double(shared) * Double(max(book.characters, 0)) / Double(totalCharacters)).rounded())
                : 0
            let images = size(of: CoverStore.url(bookID: book.id, photo: false, in: locations.covers))
                + size(of: CoverStore.url(bookID: book.id, photo: true, in: locations.covers))
            return BookUsage(id: book.id, title: book.title, author: book.author, format: book.format, bytes: share + images)
        }
        usages.sort { a, b in
            if a.bytes != b.bytes { return a.bytes > b.bytes }
            let order = a.title.localizedStandardCompare(b.title)
            if order != .orderedSame { return order == .orderedAscending }
            return a.id.uuidString < b.id.uuidString
        }
        return StorageReport(database: database, searchIndex: searchIndex, covers: covers, books: usages)
    }

    /// An SQLite file with its write-ahead log and shared-memory files.
    static func sqliteSize(_ url: URL) -> Int64 {
        let path = url.path
        return [path, path + "-wal", path + "-shm"].reduce(Int64(0)) { $0 + size(of: URL(fileURLWithPath: $1)) }
    }

    /// Bytes allocated on disk for a file, or for all files in a folder. 0 when it is missing.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
            var total: Int64 = 0
            for case let file as URL in enumerator {
                guard let fileValues = try? file.resourceValues(forKeys: keys), fileValues.isDirectory != true else { continue }
                total += bytes(fileValues)
            }
            return total
        }
        return bytes(values)
    }

    private static func bytes(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// "1.2 MB", in the units the Files app uses.
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
