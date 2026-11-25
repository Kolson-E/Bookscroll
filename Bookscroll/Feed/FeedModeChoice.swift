import Foundation

/// The feed's mode from the stored choices. A Focus filter's shelf comes first; a choice
/// that points at a book or shelf that is gone falls back to Mix.
enum FeedModeChoice {
    /// The books chosen with "Choose Books" in the feed menu, as comma-separated ids.
    static let chosenBooksKey = "feedBookIDs"
    /// The id of the chosen books in shelf mode. It is no real shelf's id.
    static let chosenBooksID = UUID(uuidString: "00000000-0000-0000-0000-0000B00C5E1F")!

    static func resolve(
        modeRaw: String,
        singleBookID: String,
        feedShelfID: String,
        focusShelfID: String,
        shelves: [ShelfRecord],
        chosenBookIDs: String = ""
    ) -> FeedMode {
        if let id = UUID(uuidString: focusShelfID), let shelf = shelves.first(where: { $0.id == id }) {
            return .shelf(ShelfSelection(id: shelf.id, name: shelf.name, bookIDs: shelf.bookIDs))
        }
        if modeRaw == "single", let id = UUID(uuidString: singleBookID) {
            return .single(id)
        }
        if modeRaw == "shelf", let id = UUID(uuidString: feedShelfID), let shelf = shelves.first(where: { $0.id == id }) {
            return .shelf(ShelfSelection(id: shelf.id, name: shelf.name, bookIDs: shelf.bookIDs))
        }
        if modeRaw == "books" {
            let ids = bookIDs(from: chosenBookIDs)
            if ids.count == 1 { return .single(ids[0]) }
            if ids.count > 1 { return .shelf(chosenBooks(ids)) }
        }
        return .mix
    }

    /// The chosen books as a shelf-mode selection, named by how many there are.
    static func chosenBooks(_ ids: [UUID]) -> ShelfSelection {
        ShelfSelection(id: chosenBooksID, name: String(localized: "\(ids.count) books"), bookIDs: ids)
    }

    /// Ids from storage, in order, without repeats or invalid entries.
    static func bookIDs(from storage: String) -> [UUID] {
        var seen = Set<UUID>()
        return storage.split(separator: ",").compactMap { UUID(uuidString: String($0)) }.filter { seen.insert($0).inserted }
    }

    static func storage(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: ",")
    }
}
