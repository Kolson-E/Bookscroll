import Foundation
import Observation
import SwiftData
import SwiftUI

/// Value copy of a stored shelf.
struct ShelfRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var bookIDs: [UUID]
    var sortIndex: Int

    init(id: UUID, name: String, bookIDs: [UUID], sortIndex: Int) {
        self.id = id
        self.name = name
        self.bookIDs = bookIDs
        self.sortIndex = sortIndex
    }

    init(_ shelf: Shelf) {
        self.init(id: shelf.id, name: shelf.name, bookIDs: shelf.bookIDs, sortIndex: shelf.sortIndex)
    }

    func contains(_ bookID: UUID) -> Bool { bookIDs.contains(bookID) }
}

/// The reader's shelves: named, ordered lists of books. A book can be on any number of
/// shelves. Changes save at once.
@MainActor
@Observable
final class ShelfStore {
    private(set) var shelves: [ShelfRecord] = []
    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        let descriptor = FetchDescriptor<Shelf>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)])
        shelves = ((try? context.fetch(descriptor)) ?? []).map(ShelfRecord.init)
    }

    func shelf(id: UUID) -> ShelfRecord? {
        shelves.first { $0.id == id }
    }

    /// A free name: "Favourites", else "Favourites 2", "Favourites 3", …
    func uniqueName(_ name: String, excluding id: UUID? = nil) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(shelves.filter { $0.id != id }.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    /// Makes a shelf at the end of the list. Returns nil when the name is empty.
    @discardableResult
    func create(name: String, bookIDs: [UUID] = []) -> UUID? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let shelf = Shelf(
            name: uniqueName(name),
            sortIndex: (shelves.map(\.sortIndex).max() ?? -1) + 1,
            bookIDs: Self.withoutDuplicates(bookIDs)
        )
        context.insert(shelf)
        commit()
        return shelf.id
    }

    func rename(_ id: UUID, to name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let newName = uniqueName(name, excluding: id)
        update(id) { $0.name = newName }
    }

    func delete(_ id: UUID) {
        guard let shelf = model(id) else { return }
        context.delete(shelf)
        commit()
    }

    /// Reorders shelves, as `List.onMove` gives it.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = shelves.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        let models = fetchAll()
        for (index, id) in ids.enumerated() {
            models.first { $0.id == id }?.sortIndex = index
        }
        commit()
    }

    /// Adds books at the end of the shelf; books already on it stay where they are.
    func add(_ bookIDs: [UUID], to shelfID: UUID) {
        update(shelfID) { shelf in
            shelf.bookIDs = Self.withoutDuplicates(shelf.bookIDs + bookIDs)
        }
    }

    func remove(_ bookIDs: Set<UUID>, from shelfID: UUID) {
        update(shelfID) { $0.bookIDs.removeAll { bookIDs.contains($0) } }
    }

    /// Puts the book on the shelf, or takes it off.
    func toggle(_ bookID: UUID, on shelfID: UUID) {
        if shelf(id: shelfID)?.contains(bookID) == true {
            remove([bookID], from: shelfID)
        } else {
            add([bookID], to: shelfID)
        }
    }

    /// Makes the shelf hold exactly `bookIDs`: books that stay keep their place, new ones go
    /// at the end in the order given.
    func setMembers(_ bookIDs: [UUID], of shelfID: UUID) {
        let wanted = Set(bookIDs)
        update(shelfID) { shelf in
            let kept = shelf.bookIDs.filter { wanted.contains($0) }
            let keptSet = Set(kept)
            shelf.bookIDs = Self.withoutDuplicates(kept + bookIDs.filter { !keptSet.contains($0) })
        }
    }

    /// Reorders the books of one shelf.
    func moveBooks(on shelfID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        update(shelfID) { $0.bookIDs.move(fromOffsets: source, toOffset: destination) }
    }

    /// Takes a deleted book off every shelf.
    func removeEverywhere(_ bookID: UUID) {
        let models = fetchAll().filter { $0.bookIDs.contains(bookID) }
        guard !models.isEmpty else { return }
        for shelf in models {
            shelf.bookIDs.removeAll { $0 == bookID }
        }
        commit()
    }

    /// Puts `new` in the place of `old` on every shelf (a replaced file).
    func replaceEverywhere(_ old: UUID, with new: UUID) {
        let models = fetchAll().filter { $0.bookIDs.contains(old) }
        guard !models.isEmpty else { return }
        for shelf in models {
            var ids = shelf.bookIDs.map { $0 == old ? new : $0 }
            var seen = Set<UUID>()
            ids = ids.filter { seen.insert($0).inserted }
            shelf.bookIDs = ids
        }
        commit()
    }

    // MARK: Private

    private func fetchAll() -> [Shelf] {
        (try? context.fetch(FetchDescriptor<Shelf>())) ?? []
    }

    private func model(_ id: UUID) -> Shelf? {
        var descriptor = FetchDescriptor<Shelf>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func update(_ id: UUID, _ change: (Shelf) -> Void) {
        guard let shelf = model(id) else { return }
        change(shelf)
        commit()
    }

    private func commit() {
        try? context.save()
        reload()
    }

    private static func withoutDuplicates(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
