import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A backup of what the reader has done in Bookscroll: for every book its place, finish date,
/// Mix settings, details, avatar photo and marks, the shelves and the reading list. The books' text is not in
/// it: after a reinstall or on a new device, import the books again, then restore.
struct LibraryBackup: Codable, Equatable, Sendable {
    struct ShelfBackup: Codable, Equatable, Sendable {
        var name: String
        /// Indexes into `books`, in shelf order.
        var books: [Int]
    }

    static let currentVersion = 1

    var version = LibraryBackup.currentVersion
    var createdAt: Date
    var books: [BookState]
    var shelves: [ShelfBackup]
    /// The reading list's sets, in order (name and books). Nil in backups made before the
    /// reading list.
    var readingList: [ShelfBackup]? = nil

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> LibraryBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: LibraryBackup
        do {
            backup = try decoder.decode(LibraryBackup.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
        guard backup.version <= currentVersion else { throw BackupError.newerVersion }
        return backup
    }

    static func fileName(for date: Date) -> String {
        "Bookscroll Backup " + date.formatted(.iso8601.year().month().day()) + ".json"
    }

    /// The facts used to find a backed-up book in the library.
    struct LibraryBook: Sendable {
        let id: UUID
        let title: String
        let author: String
        let format: String
        let totalCharacters: Int
    }

    /// For each backed-up book, the library book it belongs to, or nil. Tried in order: same
    /// title, author and length; same title and author; same format and length (the details
    /// were edited). Each library book is used once.
    static func match(_ books: [BookState], to library: [LibraryBook]) -> [UUID?] {
        var used = Set<UUID>()
        var result = [UUID?](repeating: nil, count: books.count)
        let rules: [(BookState, LibraryBook) -> Bool] = [
            { $0.title == $1.title && $0.author == $1.author && $0.totalCharacters == $1.totalCharacters },
            { $0.title == $1.title && $0.author == $1.author },
            { $0.format == $1.format && $0.totalCharacters == $1.totalCharacters },
        ]
        for rule in rules {
            for (index, state) in books.enumerated() where result[index] == nil {
                if let book = library.first(where: { !used.contains($0.id) && rule(state, $0) }) {
                    result[index] = book.id
                    used.insert(book.id)
                }
            }
        }
        return result
    }
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .notABackup: return "This file is not a Bookscroll backup."
        case .newerVersion: return "This backup was made by a newer version of Bookscroll. Update the app, then try again."
        }
    }
}

/// What a restore did.
struct RestoreSummary: Equatable, Sendable {
    var restored: Int
    /// Titles of backed-up books that are not in the library.
    var missing: [String]
    var shelves: Int

    var message: String {
        var parts = [restored == 1 ? "1 book restored." : "\(restored) books restored."]
        if shelves > 0 { parts.append(shelves == 1 ? "1 shelf restored." : "\(shelves) shelves restored.") }
        if !missing.isEmpty {
            let list = missing.prefix(5).map { "\u{201C}\($0)\u{201D}" }.joined(separator: ", ")
            let more = missing.count > 5 ? " and \(missing.count - 5) more" : ""
            parts.append("Not in your library: \(list)\(more). Import them, then restore again.")
        }
        return parts.joined(separator: " ")
    }
}

/// The backup as a file for the Files exporter.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw BackupError.notABackup }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
