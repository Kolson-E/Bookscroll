import Foundation
import WidgetKit

/// Builds what the widgets show and writes it to the shared folder.
enum WidgetContent {
    struct BookFacts: Sendable {
        let id: UUID
        let title: String
        let author: String
        let totalCharacters: Int
        let positionOffset: Int
        let lastReadAt: Date?
        let finishedAt: Date?
    }

    /// The unfinished book read last, if any was read.
    static func currentBook(_ books: [BookFacts]) -> BookFacts? {
        books
            .filter { $0.finishedAt == nil && $0.positionOffset > 0 && $0.lastReadAt != nil }
            .max { ($0.lastReadAt ?? .distantPast, $1.id.uuidString) < ($1.lastReadAt ?? .distantPast, $0.id.uuidString) }
    }

    /// Characters of the next paragraph shown on the medium widget.
    static let upNextLength = 280

    static func snapshot(
        book: BookFacts?,
        upNext: String,
        timeLeft: TimeInterval,
        secondsToday: Double,
        streak: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            book: book.map {
                WidgetSnapshot.CurrentBook(
                    id: $0.id,
                    title: $0.title,
                    author: $0.author,
                    percent: TextUtils.percent($0.positionOffset, of: $0.totalCharacters),
                    timeLeft: "about \(ReadingStats.formatDuration(timeLeft)) left",
                    upNext: String(upNext.prefix(upNextLength))
                )
            },
            day: WidgetSnapshot.dayKey(now, calendar: calendar),
            minutesToday: Int((secondsToday / 60).rounded()),
            streak: streak,
            updatedAt: now
        )
    }
}

/// Writes the widget snapshot when it changes, and asks WidgetKit to redraw.
@MainActor
final class WidgetBridge {
    private let url: URL?
    private var written: WidgetSnapshot?

    /// `url` nil writes nothing (tests, or no app group).
    init(url: URL?) {
        self.url = url
    }

    func update(_ snapshot: WidgetSnapshot) {
        guard let url else { return }
        var comparable = snapshot
        comparable.updatedAt = written?.updatedAt ?? snapshot.updatedAt
        guard comparable != written else { return }
        if SharedContainer.write(snapshot, to: url) {
            written = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
