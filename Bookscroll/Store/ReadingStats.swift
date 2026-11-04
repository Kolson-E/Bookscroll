import Foundation
import Observation

/// Reading time and amount, per day. Kept in a small JSON file beside the library.
///
/// - Amount: characters the feed moved past (a book's place moving forward). A move of more
///   than `largestStep` characters at once is a jump, not reading, and is not counted.
/// - Time: the time between two such moves, when the gap is at most `idleGap`. The first move
///   after a pause adds no time, so time with the app open but unused is not counted.
@MainActor
@Observable
final class ReadingStats {
    struct Day: Codable, Equatable, Sendable {
        /// Local date, "2026-11-04".
        var day: String
        var seconds: Double
        var characters: Int
        /// Characters of steps that came with time (not the first step after a pause): the
        /// speed is these over `seconds`.
        var timedCharacters: Int = 0
    }

    /// Longest gap between two reading steps that still counts as reading.
    static let idleGap: TimeInterval = 120
    /// Largest single step that counts as reading.
    static let largestStep = 20_000
    /// Speed used until there is enough reading to measure: about 200 words a minute.
    static let defaultCharactersPerMinute: Double = 1_200
    /// Reading time needed before the measured speed is used.
    static let minimumMeasuredSeconds: Double = 600
    /// Characters per word, for word counts shown to the reader.
    static let charactersPerWord: Double = 6

    private(set) var days: [Day] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var calendar: Calendar
    @ObservationIgnored private var lastStep: Date?
    @ObservationIgnored private var unsavedSteps = 0

    nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("ReadingStats.json")
    }

    /// `fileURL` nil keeps the stats in memory only (tests, UI tests).
    init(fileURL: URL? = ReadingStats.defaultURL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            days = ((try? JSONDecoder().decode([Day].self, from: data)) ?? []).sorted { $0.day < $1.day }
        }
    }

    // MARK: Recording

    /// The feed moved forward by `characters` at `date`.
    func record(characters: Int, at date: Date = .now) {
        guard characters > 0, characters <= Self.largestStep else { return }
        var seconds: Double = 0
        if let lastStep {
            let gap = date.timeIntervalSince(lastStep)
            if gap > 0, gap <= Self.idleGap { seconds = gap }
        }
        lastStep = date
        let key = dayKey(date)
        let timed = seconds > 0 ? characters : 0
        if let index = days.lastIndex(where: { $0.day == key }) {
            days[index].seconds += seconds
            days[index].characters += characters
            days[index].timedCharacters += timed
        } else {
            days.append(Day(day: key, seconds: seconds, characters: characters, timedCharacters: timed))
            days.sort { $0.day < $1.day }
        }
        unsavedSteps += 1
        if unsavedSteps >= 20 { save() }
    }

    /// The reader stopped (app in the background, another tab). The next step adds no time.
    func pause() {
        lastStep = nil
        save()
    }

    func save() {
        unsavedSteps = 0
        guard let fileURL, let data = try? JSONEncoder().encode(days) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: Questions

    var totalSeconds: Double { days.reduce(0) { $0 + $1.seconds } }
    var totalCharacters: Int { days.reduce(0) { $0 + $1.characters } }

    /// Measured speed, or nil while there is less than `minimumMeasuredSeconds` of reading.
    var measuredCharactersPerMinute: Double? {
        let seconds = totalSeconds
        guard seconds >= Self.minimumMeasuredSeconds else { return nil }
        let characters = days.reduce(0) { $0 + $1.timedCharacters }
        return characters > 0 ? Double(characters) / (seconds / 60) : nil
    }

    var charactersPerMinute: Double { measuredCharactersPerMinute ?? Self.defaultCharactersPerMinute }

    var wordsPerMinute: Int { Int((charactersPerMinute / Self.charactersPerWord).rounded()) }

    /// Reading time for `characters` at the reader's speed.
    func timeToRead(characters: Int) -> TimeInterval {
        Double(max(0, characters)) / charactersPerMinute * 60
    }

    func day(_ date: Date) -> Day {
        let key = dayKey(date)
        return days.last { $0.day == key } ?? Day(day: key, seconds: 0, characters: 0)
    }

    /// The `count` days up to and including `date`, oldest first, with empty days filled in.
    func lastDays(_ count: Int, until date: Date = .now) -> [(date: Date, day: Day)] {
        let today = calendar.startOfDay(for: date)
        return (0..<count).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return (date, day(date))
        }
    }

    /// Seconds and characters in the 7 days up to and including `date`.
    func week(until date: Date = .now) -> Day {
        let days = lastDays(7, until: date).map(\.day)
        return Day(
            day: "week",
            seconds: days.reduce(0) { $0 + $1.seconds },
            characters: days.reduce(0) { $0 + $1.characters },
            timedCharacters: days.reduce(0) { $0 + $1.timedCharacters }
        )
    }

    /// Days in a row with reading, ending today, or yesterday when today has none yet.
    func streak(until date: Date = .now) -> Int {
        let read = Set(days.filter { $0.characters > 0 }.map(\.day))
        var current = calendar.startOfDay(for: date)
        if !read.contains(dayKey(current)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: current) else { return 0 }
            current = yesterday
        }
        var count = 0
        while read.contains(dayKey(current)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: current) else { break }
            current = previous
        }
        return count
    }

    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Formatting

    /// "about 3 h 20 min", rounded to 5 minutes (1 minute under 10 minutes).
    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        let step: Double = minutes < 10 ? 1 : 5
        let rounded = max(1, (minutes / step).rounded() * step)
        let hours = Int(rounded) / 60
        let rest = Int(rounded) % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Time spent reading: "0 min", "45 min", "2 h 5 min" (not rounded to 5).
    nonisolated static func formatReadingTime(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        if hours == 0 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min"
    }
}
