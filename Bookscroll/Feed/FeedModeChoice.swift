import Foundation

/// The feed's mode from the stored choices. A Focus filter's shelf comes first; a choice
/// that points at a book or shelf that is gone falls back to Mix.
enum FeedModeChoice {
    static func resolve(
        modeRaw: String,
        singleBookID: String,
        feedShelfID: String,
        focusShelfID: String,
        shelves: [ShelfRecord]
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
        return .mix
    }
}
