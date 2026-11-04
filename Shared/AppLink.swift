import Foundation

/// A place in Bookscroll that a link opens: from a widget, the Live Activity, Spotlight or a
/// shortcut. As a URL: `bookscroll://continue`, `bookscroll://book/<id>`,
/// `bookscroll://highlight/<id>`.
enum AppLink: Equatable, Sendable {
    /// The book read last, at its place.
    case continueReading
    /// A book in One book mode, at its place.
    case book(UUID)
    /// The reader around a highlight.
    case highlight(UUID)

    static let scheme = "bookscroll"

    var url: URL {
        switch self {
        case .continueReading: return URL(string: "\(Self.scheme)://continue")!
        case let .book(id): return URL(string: "\(Self.scheme)://book/\(id.uuidString)")!
        case let .highlight(id): return URL(string: "\(Self.scheme)://highlight/\(id.uuidString)")!
        }
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
        switch (host, id) {
        case ("continue", _): self = .continueReading
        case let ("book", id?): self = .book(id)
        case let ("highlight", id?): self = .highlight(id)
        default: return nil
        }
    }

    /// The Spotlight item identifier: "book:<id>" or "highlight:<id>".
    var spotlightID: String? {
        switch self {
        case .continueReading: return nil
        case let .book(id): return "book:\(id.uuidString)"
        case let .highlight(id): return "highlight:\(id.uuidString)"
        }
    }

    init?(spotlightID: String) {
        let parts = spotlightID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "book": self = .book(id)
        case "highlight": self = .highlight(id)
        default: return nil
        }
    }
}
