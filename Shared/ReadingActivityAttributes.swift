import ActivityKit
import Foundation

/// The Live Activity of a reading session: the book, how far in, and today's reading time.
struct ReadingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0–100.
        var percent: Int
        var minutesToday: Int
        /// "about 2 h 10 min left".
        var timeLeft: String
        /// The app went to the background: the session is over.
        var isPaused: Bool
    }

    var bookID: UUID
    var title: String
    var author: String
}
