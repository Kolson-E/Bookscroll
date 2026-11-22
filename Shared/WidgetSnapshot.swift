import Foundation

/// What the widgets show, written by the app into the app group folder. The widgets cannot
/// read the library itself.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct CurrentBook: Codable, Equatable, Sendable {
        var id: UUID
        var title: String
        var author: String
        /// 0–100.
        var percent: Int
        /// "about 2 h 10 min left".
        var timeLeft: String
        /// The start of the paragraph at the reader's place.
        var upNext: String
    }

    /// The book read last that is not finished, or nil.
    var book: CurrentBook?
    /// Local date of `minutesToday`, "2026-11-04": on a later day the widgets show 0.
    var day: String
    var minutesToday: Int
    var streak: Int
    var updatedAt: Date

    static let fileName = "WidgetSnapshot.json"

    /// Today's minutes, or 0 when the snapshot is from an earlier day.
    func minutes(on day: String) -> Int {
        day == self.day ? minutesToday : 0
    }

    /// The streak still counts on the day after the last reading day; later it is 0.
    func streak(on day: String, calendar: Calendar = .current) -> Int {
        guard day != self.day else { return streak }
        guard let last = Self.date(self.day, calendar: calendar), let now = Self.date(day, calendar: calendar),
              let next = calendar.date(byAdding: .day, value: 1, to: last) else { return 0 }
        return calendar.isDate(now, inSameDayAs: next) ? streak : 0
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static let placeholder = WidgetSnapshot(
        book: CurrentBook(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Your Book",
            author: "Author",
            percent: 42,
            timeLeft: "about 3 h left",
            upNext: "The next paragraph of the book you are reading shows here."
        ),
        day: "",
        minutesToday: 25,
        streak: 4,
        updatedAt: .distantPast
    )
}

/// The folder the app and its widgets share.
enum SharedContainer {
    /// From the BookscrollAppGroup Info.plist key (set from APP_GROUP_ID).
    static var groupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "BookscrollAppGroup") as? String
    }

    static var folder: URL? {
        guard let groupID, !groupID.isEmpty, !groupID.contains("$(") else { return nil }
        for candidate in groupCandidates(groupID: groupID, bundleID: Bundle.main.bundleIdentifier) {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: candidate) {
                return url
            }
        }
        return nil
    }

    /// The group from Info.plist first. Sideloading tools (AltStore, SideStore) re-sign the app
    /// with a free Apple ID: they add the team id to the bundle ids and to the app group
    /// (`group.<base>.<TEAMID>`), but not to the Info.plist key. The team id is taken from the
    /// bundle id: a 10-character upper-case part after the base bundle id.
    static func groupCandidates(groupID: String, bundleID: String?) -> [String] {
        var candidates = [groupID]
        let prefix = "group."
        guard groupID.hasPrefix(prefix), let bundleID else { return candidates }
        let base = String(groupID.dropFirst(prefix.count))
        guard bundleID.hasPrefix(base + ".") else { return candidates }
        let parts = bundleID.dropFirst(base.count + 1).split(separator: ".")
        for part in parts where part.count == 10 && part.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) {
            let candidate = "\(groupID).\(part)"
            if !candidates.contains(candidate) { candidates.append(candidate) }
        }
        return candidates
    }

    static var snapshotURL: URL? {
        folder?.appendingPathComponent(WidgetSnapshot.fileName)
    }

    static func readSnapshot(from url: URL? = snapshotURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Returns false when there is no shared folder or the file could not be written.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot, to url: URL? = snapshotURL) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let url, let data = try? encoder.encode(snapshot) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
