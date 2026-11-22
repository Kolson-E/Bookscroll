import AppIntents
import Foundation

// Shortcuts, Siri and Focus filters. The intents run in the app's process and use the app's
// model (`AppModel.current`).

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case notReady
    case bookNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady: return "Bookscroll is not ready yet. Try again."
        case .bookNotFound: return "That book is not in your library."
        }
    }
}

// MARK: Entities

struct BookEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Book"
    static var defaultQuery = BookQuery()

    let id: UUID
    let title: String
    let author: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(author)")
    }
}

struct BookQuery: EntityStringQuery {
    @MainActor
    private func all() -> [BookEntity] {
        (AppModel.current?.store.allBooks() ?? []).map { BookEntity(id: $0.id, title: $0.title, author: $0.author) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BookEntity] {
        let wanted = Set(identifiers)
        return all().filter { wanted.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [BookEntity] {
        all().filter { $0.title.localizedStandardContains(string) || $0.author.localizedStandardContains(string) }
    }

    /// The books read most recently first.
    @MainActor
    func suggestedEntities() async throws -> [BookEntity] {
        let books = (AppModel.current?.store.allBooks() ?? [])
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        return books.prefix(20).map { BookEntity(id: $0.id, title: $0.title, author: $0.author) }
    }
}

struct ShelfEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Shelf"
    static var defaultQuery = ShelfQuery()

    let id: UUID
    let name: String
    let count: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(count) books")
    }
}

struct ShelfQuery: EntityQuery {
    @MainActor
    private func all() -> [ShelfEntity] {
        (AppModel.current?.shelves.shelves ?? []).map { ShelfEntity(id: $0.id, name: $0.name, count: $0.bookIDs.count) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ShelfEntity] {
        let wanted = Set(identifiers)
        return all().filter { wanted.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ShelfEntity] {
        all()
    }
}

// MARK: Intents

struct ContinueReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "Continue Reading"
    static var description = IntentDescription("Opens the book you read last at your place.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppModel.current else { throw IntentError.notReady }
        app.open(.continueReading)
        return .result()
    }
}

struct OpenBookIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Book"
    static var description = IntentDescription("Opens a book in One book mode at your place.")
    static var openAppWhenRun = true

    @Parameter(title: "Book")
    var book: BookEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$book)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppModel.current else { throw IntentError.notReady }
        guard app.store.book(id: book.id) != nil else { throw IntentError.bookNotFound }
        app.open(.book(book.id))
        return .result()
    }
}

struct ReadingTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Reading Today"
    static var description = IntentDescription("Tells you how long you read today and your streak.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let app = AppModel.current else { throw IntentError.notReady }
        let today = app.stats.day(.now)
        let minutes = Int((today.seconds / 60).rounded())
        let streak = app.stats.streak()
        let time = ReadingStats.formatReadingTime(today.seconds)
        let streakText = streak == 1 ? "1 day" : "\(streak) days"
        return .result(value: minutes, dialog: "You read \(time) today. Streak: \(streakText).")
    }
}

struct BookscrollShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: ["Continue reading in \(.applicationName)", "Resume my book in \(.applicationName)"],
            shortTitle: "Continue Reading",
            systemImageName: "book"
        )
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: ["Open a book in \(.applicationName)"],
            shortTitle: "Open Book",
            systemImageName: "books.vertical"
        )
        AppShortcut(
            intent: ReadingTodayIntent(),
            phrases: ["How much did I read today in \(.applicationName)"],
            shortTitle: "Reading Today",
            systemImageName: "chart.bar"
        )
    }
}

// MARK: Focus filter

/// Settings › Focus › (a Focus) › Focus Filters › Bookscroll: while that Focus is on, the
/// feed shows one shelf. When the Focus ends, the feed goes back to your own choice.
struct FeedFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Feed"
    static var description: IntentDescription? = IntentDescription("While this Focus is on, the feed shows only the books on a shelf.")

    @Parameter(title: "Shelf")
    var shelf: ShelfEntity?

    var displayRepresentation: DisplayRepresentation {
        if let shelf {
            return DisplayRepresentation(title: "Feed: \(shelf.name)")
        }
        return DisplayRepresentation(title: "Feed: your own choice", subtitle: "Choose a shelf")
    }

    func perform() async throws -> some IntentResult {
        FocusFeed.set(shelfID: shelf?.id)
        return .result()
    }
}

/// The shelf a Focus filter sets for the feed. The feed reads it before your own choice.
enum FocusFeed {
    static let key = "focusShelfID"

    static func set(shelfID: UUID?, defaults: UserDefaults = .standard) {
        if let shelfID {
            defaults.set(shelfID.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
