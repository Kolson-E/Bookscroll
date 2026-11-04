import ActivityKit
import Foundation

/// When to start or update the reading Live Activity.
enum ReadingActivityPlan: Equatable {
    case none
    case start
    case update

    /// Updates at most every `interval` seconds, except when the percent changes.
    static let interval: TimeInterval = 30

    static func decide(
        currentBook: UUID?,
        lastState: ReadingActivityAttributes.ContentState?,
        lastUpdate: Date,
        book: UUID,
        state: ReadingActivityAttributes.ContentState,
        now: Date
    ) -> ReadingActivityPlan {
        guard currentBook == book, let lastState else { return .start }
        if state == lastState { return .none }
        if state.percent != lastState.percent || now.timeIntervalSince(lastUpdate) >= interval { return .update }
        return .none
    }
}

/// Shows the book being read on the Lock Screen and in the Dynamic Island. Reading starts it;
/// leaving the app ends it with a "Paused" state that stays for an hour; coming back removes it.
@MainActor
final class ReadingActivityController {
    /// Read on each step, so the Settings toggle takes effect at once.
    var isEnabled: @MainActor () -> Bool = { true }

    private let available: Bool
    private var activity: Activity<ReadingActivityAttributes>?
    private var lastState: ReadingActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    /// How long the paused state stays on the Lock Screen.
    static let pausedDuration: TimeInterval = 3_600

    /// `enabled` false never shows an activity (tests).
    init(enabled: Bool) {
        available = enabled
    }

    private var canShow: Bool {
        available && isEnabled() && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func reading(_ attributes: ReadingActivityAttributes, state: ReadingActivityAttributes.ContentState, now: Date = .now) {
        guard canShow else {
            if activity != nil { endAll() }
            return
        }
        let plan = ReadingActivityPlan.decide(
            currentBook: activity?.attributes.bookID,
            lastState: lastState,
            lastUpdate: lastUpdate,
            book: attributes.bookID,
            state: state,
            now: now
        )
        switch plan {
        case .none:
            return
        case .start:
            endAll()
            activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
        case .update:
            let current = activity
            Task { await current?.update(ActivityContent(state: state, staleDate: nil)) }
        }
        lastState = state
        lastUpdate = now
    }

    /// The app left the foreground: show the session as paused for a while.
    func pause(now: Date = .now) {
        guard let activity, var state = lastState else { return }
        state.isPaused = true
        let content = ActivityContent(state: state, staleDate: nil)
        let until = now.addingTimeInterval(Self.pausedDuration)
        Task { await activity.end(content, dismissalPolicy: .after(until)) }
        self.activity = nil
        lastState = nil
    }

    /// Removes every reading activity at once (the app is back, or the setting is off).
    func endAll() {
        activity = nil
        lastState = nil
        guard available else { return }
        let activities = Activity<ReadingActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
