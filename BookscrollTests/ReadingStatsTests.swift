import XCTest
@testable import Bookscroll

/// Reading time, amount, speed, streak and time left.
@MainActor
final class ReadingStatsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-11-04 at 12:00 UTC, plus `days` and `seconds`.
    private func date(days: Int = 0, seconds: TimeInterval = 0) -> Date {
        let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        return calendar.date(byAdding: .day, value: days, to: noon)!.addingTimeInterval(seconds)
    }

    private func makeStats(fileURL: URL? = nil) -> ReadingStats {
        ReadingStats(fileURL: fileURL, calendar: calendar)
    }

    func testTimeCountsOnlyBetweenStepsWithShortGaps() {
        let stats = makeStats()
        stats.record(characters: 600, at: date())
        XCTAssertEqual(stats.day(date()), ReadingStats.Day(day: "2026-11-04", seconds: 0, characters: 600, timedCharacters: 0), "The first step adds no time")

        stats.record(characters: 600, at: date(seconds: 30))
        stats.record(characters: 600, at: date(seconds: 30 + 121))
        XCTAssertEqual(stats.day(date()).seconds, 30, "A gap of more than 2 minutes adds no time")
        XCTAssertEqual(stats.day(date()).characters, 1_800)
        XCTAssertEqual(stats.day(date()).timedCharacters, 600)

        stats.record(characters: 20_001, at: date(seconds: 160))
        stats.record(characters: 0, at: date(seconds: 170))
        stats.record(characters: -5, at: date(seconds: 180))
        XCTAssertEqual(stats.day(date()).characters, 1_800, "Jumps and empty steps are not reading")

        stats.record(characters: 600, at: date(seconds: 190))
        XCTAssertEqual(stats.day(date()).seconds, 30 + 39, "The gap is from the last step that counted")

        stats.pause()
        stats.record(characters: 600, at: date(seconds: 200))
        XCTAssertEqual(stats.day(date()).seconds, 69, "The first step after a pause adds no time")
        XCTAssertEqual(stats.totalCharacters, 3_000)
    }

    func testSpeedIsMeasuredAfterTenMinutes() {
        let stats = makeStats()
        XCTAssertNil(stats.measuredCharactersPerMinute)
        XCTAssertEqual(stats.wordsPerMinute, 200)
        XCTAssertEqual(stats.timeToRead(characters: 12_000), 600, accuracy: 0.001)
        XCTAssertEqual(stats.timeToRead(characters: -10), 0)

        // 2400 characters a minute: 400 words a minute.
        for step in 0...10 {
            stats.record(characters: 2_400, at: date(seconds: Double(step) * 60))
            if step == 5 { XCTAssertNil(stats.measuredCharactersPerMinute, "5 minutes is not enough") }
        }
        XCTAssertEqual(stats.totalSeconds, 600)
        XCTAssertEqual(try XCTUnwrap(stats.measuredCharactersPerMinute), 2_400, accuracy: 0.001)
        XCTAssertEqual(stats.wordsPerMinute, 400)
        XCTAssertEqual(stats.timeToRead(characters: 24_000), 600, accuracy: 0.001)
    }

    func testStreakDaysAndWeek() {
        let stats = makeStats()
        for back in [0, 1, 2, 4, 9] {
            stats.record(characters: 100, at: date(days: -back))
            stats.record(characters: 100, at: date(days: -back, seconds: 60))
        }
        XCTAssertEqual(stats.streak(until: date()), 3)
        XCTAssertEqual(stats.streak(until: date(days: 1)), 3, "Today without reading yet keeps yesterday's streak")
        XCTAssertEqual(stats.streak(until: date(days: 2)), 0)
        XCTAssertEqual(stats.streak(until: date(days: -3)), 1, "Ends the day before, which has reading")
        XCTAssertEqual(stats.streak(until: date(days: -6)), 0)
        XCTAssertEqual(stats.streak(until: date(days: -4)), 1)

        let days = stats.lastDays(14, until: date())
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.first?.day.day, "2026-10-22")
        XCTAssertEqual(days.last?.day.day, "2026-11-04")
        XCTAssertEqual(days.filter { $0.day.characters > 0 }.count, 5)
        XCTAssertEqual(days[10].day, ReadingStats.Day(day: "2026-11-01", seconds: 0, characters: 0), "Empty days are filled in")

        let week = stats.week(until: date())
        XCTAssertEqual(week.seconds, 4 * 60)
        XCTAssertEqual(week.characters, 4 * 200)
    }

    func testStatsAreSavedAndLoaded() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("ReadingStats.json")

        let stats = makeStats(fileURL: url)
        stats.record(characters: 500, at: date(days: -1))
        stats.record(characters: 700, at: date())
        stats.record(characters: 300, at: date(seconds: 45))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "Saved every 20 steps or on pause")
        stats.pause()

        let loaded = makeStats(fileURL: url)
        XCTAssertEqual(loaded.days, stats.days)
        XCTAssertEqual(loaded.days.map(\.day), ["2026-11-03", "2026-11-04"])
        XCTAssertEqual(loaded.day(date()).seconds, 45)

        try Data("not json".utf8).write(to: url)
        XCTAssertTrue(makeStats(fileURL: url).days.isEmpty, "A damaged file starts empty")
    }

    func testFormatting() {
        XCTAssertEqual(ReadingStats.formatDuration(10), "1 min")
        XCTAssertEqual(ReadingStats.formatDuration(7.4 * 60), "7 min")
        XCTAssertEqual(ReadingStats.formatDuration(12 * 60), "10 min")
        XCTAssertEqual(ReadingStats.formatDuration(62 * 60), "1 h")
        XCTAssertEqual(ReadingStats.formatDuration(200 * 60), "3 h 20 min")
        XCTAssertEqual(ReadingStats.formatReadingTime(0), "0 min")
        XCTAssertEqual(ReadingStats.formatReadingTime(44.6 * 60), "45 min")
        XCTAssertEqual(ReadingStats.formatReadingTime(3_600), "1 h")
        XCTAssertEqual(ReadingStats.formatReadingTime(125 * 60), "2 h 5 min")
    }
}
