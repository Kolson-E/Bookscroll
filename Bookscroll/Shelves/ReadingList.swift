import Foundation
import Observation

/// One set of the reading list: books read together. The feed mixes a set's books, and the
/// next set starts only when every book in this set is finished.
struct ReadingSet: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    /// Empty: the set is called by its place ("Set 3").
    var name: String
    var bookIDs: [UUID]

    init(id: UUID = UUID(), name: String = "", bookIDs: [UUID]) {
        self.id = id
        self.name = name
        self.bookIDs = bookIDs
    }
}

/// Where a set is in the reading list.
enum ReadingSetStatus: Equatable, Sendable {
    /// Every book is finished.
    case done
    /// The first set with a book that is not finished: the feed shows it.
    case current
    /// After the current set.
    case upNext
    /// No book of the set is in the library.
    case empty
}

/// The reading list: an ordered list of sets. A book is in at most one set. Kept as JSON in
/// UserDefaults, and in backups.
@MainActor
@Observable
final class ReadingListStore {
    static let key = "readingList"

    private(set) var sets: [ReadingSet] = []
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sets = Self.decode(defaults.data(forKey: Self.key))
    }

    nonisolated static func decode(_ data: Data?) -> [ReadingSet] {
        guard let data, let sets = try? JSONDecoder().decode([ReadingSet].self, from: data) else { return [] }
        return normalized(sets)
    }

    /// The name a set shows: its own name, or "Set n" by its place.
    func displayName(of set: ReadingSet) -> String {
        Self.displayName(of: set, in: sets)
    }

    nonisolated static func displayName(of set: ReadingSet, in sets: [ReadingSet]) -> String {
        let name = set.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        let number = (sets.firstIndex { $0.id == set.id } ?? sets.count) + 1
        return String(localized: "Set \(number)")
    }

    func set(id: UUID) -> ReadingSet? {
        sets.first { $0.id == id }
    }

    /// The set that holds the book, if any.
    func set(containing bookID: UUID) -> ReadingSet? {
        sets.first { $0.bookIDs.contains(bookID) }
    }

    /// Adds a set at the end. Books in other sets move to this one. Returns nil when there
    /// are no books.
    @discardableResult
    func addSet(name: String = "", bookIDs: [UUID]) -> UUID? {
        let ids = Self.withoutDuplicates(bookIDs)
        guard !ids.isEmpty else { return nil }
        let set = ReadingSet(name: name.trimmingCharacters(in: .whitespacesAndNewlines), bookIDs: ids)
        var all = sets.map { existing in
            var copy = existing
            copy.bookIDs.removeAll { ids.contains($0) }
            return copy
        }
        all.append(set)
        save(all)
        return set.id
    }

    /// Makes the set hold exactly `bookIDs`, in that order. Books in other sets move here.
    /// No books: the set goes.
    func setBooks(_ bookIDs: [UUID], of setID: UUID) {
        let ids = Self.withoutDuplicates(bookIDs)
        let all = sets.map { existing -> ReadingSet in
            var copy = existing
            if existing.id == setID {
                copy.bookIDs = ids
            } else {
                copy.bookIDs.removeAll { ids.contains($0) }
            }
            return copy
        }
        save(all)
    }

    func rename(_ setID: UUID, to name: String) {
        save(sets.map { existing in
            var copy = existing
            if existing.id == setID { copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            return copy
        })
    }

    func delete(_ setID: UUID) {
        save(sets.filter { $0.id != setID })
    }

    /// Moves a set one place up (-1) or down (+1).
    func moveSet(_ setID: UUID, by step: Int) {
        guard let index = sets.firstIndex(where: { $0.id == setID }) else { return }
        let target = index + step
        guard sets.indices.contains(target) else { return }
        var all = sets
        all.swapAt(index, target)
        save(all)
    }

    /// Reorders the sets, as `List.onMove` gives it.
    func moveSets(fromOffsets source: IndexSet, toOffset destination: Int) {
        var all = sets
        all.move(fromOffsets: source, toOffset: destination)
        save(all)
    }

    /// Reorders the books of one set, as `List.onMove` gives it.
    func moveBooks(in setID: UUID, fromOffsets source: IndexSet, toOffset destination: Int) {
        save(sets.map { existing in
            var copy = existing
            if existing.id == setID { copy.bookIDs.move(fromOffsets: source, toOffset: destination) }
            return copy
        })
    }

    func remove(_ bookID: UUID, from setID: UUID) {
        save(sets.map { existing in
            var copy = existing
            if existing.id == setID { copy.bookIDs.removeAll { $0 == bookID } }
            return copy
        })
    }

    /// Takes a deleted book out of the reading list.
    func removeEverywhere(_ bookID: UUID) {
        guard set(containing: bookID) != nil else { return }
        save(sets.map { existing in
            var copy = existing
            copy.bookIDs.removeAll { $0 == bookID }
            return copy
        })
    }

    /// Puts `new` in the place of `old` (a replaced file).
    func replaceEverywhere(_ old: UUID, with new: UUID) {
        guard set(containing: old) != nil else { return }
        save(sets.map { existing in
            var copy = existing
            copy.bookIDs = Self.withoutDuplicates(existing.bookIDs.map { $0 == old ? new : $0 })
            return copy
        })
    }

    /// Removes the sets whose books are all finished.
    func removeDoneSets(finished: Set<UUID>, library: Set<UUID>) {
        save(sets.filter { Self.status(of: $0, finished: finished, library: library) != .done })
    }

    /// The status of every set, in order. The current set is the first set with a book
    /// that is not finished.
    nonisolated static func statuses(of sets: [ReadingSet], finished: Set<UUID>, library: Set<UUID>) -> [ReadingSetStatus] {
        var foundCurrent = false
        return sets.map { set in
            let status = status(of: set, finished: finished, library: library)
            guard status == .upNext else { return status }
            if foundCurrent { return .upNext }
            foundCurrent = true
            return .current
        }
    }

    /// `.done`, `.empty`, or `.upNext` for a set with a book still to finish.
    nonisolated static func status(of set: ReadingSet, finished: Set<UUID>, library: Set<UUID>) -> ReadingSetStatus {
        let books = set.bookIDs.filter { library.contains($0) }
        if books.isEmpty { return .empty }
        return books.allSatisfy { finished.contains($0) } ? .done : .upNext
    }

    // MARK: Private

    private func save(_ all: [ReadingSet]) {
        sets = Self.normalized(all)
        if let data = try? JSONEncoder().encode(sets) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// No empty sets, and each book in one set only (the first).
    nonisolated private static func normalized(_ all: [ReadingSet]) -> [ReadingSet] {
        var seen = Set<UUID>()
        return all.compactMap { set in
            var copy = set
            copy.bookIDs = set.bookIDs.filter { seen.insert($0).inserted }
            return copy.bookIDs.isEmpty ? nil : copy
        }
    }

    nonisolated private static func withoutDuplicates(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
