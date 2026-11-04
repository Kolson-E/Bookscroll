import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BookscrollWidgetBundle: WidgetBundle {
    var body: some Widget {
        CurrentBookWidget()
        ReadingActivityWidget()
    }
}

// MARK: Current book

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    var day: String { WidgetSnapshot.dayKey(date) }
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = SharedContainer.readSnapshot()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview && snapshot == nil ? .placeholder : snapshot))
    }

    /// The app reloads the timeline when the reading changes; a second entry at midnight
    /// starts the new day at 0 minutes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let snapshot = SharedContainer.readSnapshot()
        let now = Date.now
        var entries = [SnapshotEntry(date: now, snapshot: snapshot)]
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            entries.append(SnapshotEntry(date: midnight, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct CurrentBookWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentBook", provider: SnapshotProvider()) { entry in
            CurrentBookView(entry: entry)
        }
        .configurationDisplayName("Current Book")
        .description("The book you are reading, how far you are, and today\u{2019}s reading time.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CurrentBookView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    private var book: WidgetSnapshot.CurrentBook? { entry.snapshot?.book }
    private var minutes: Int { entry.snapshot?.minutes(on: entry.day) ?? 0 }
    private var streak: Int { entry.snapshot?.streak(on: entry.day) ?? 0 }
    private var link: URL { book.map { AppLink.book($0.id).url } ?? AppLink.continueReading.url }

    var body: some View {
        content
            .widgetURL(link)
            .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            if let book {
                Text("\(book.title) \u{00B7} \(book.percent)%")
            } else {
                Text("Bookscroll")
            }
        case .accessoryCircular:
            if let book {
                Gauge(value: Double(book.percent), in: 0...100) {
                    Image(systemName: "book")
                } currentValueLabel: {
                    Text("\(book.percent)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .accessibilityLabel("\(book.title), \(book.percent) percent read")
            } else {
                Image(systemName: "books.vertical")
                    .font(.title2)
                    .accessibilityLabel("Bookscroll")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let book {
                    Text(book.title).font(.headline).lineLimit(1)
                    Text("\(book.percent)% \u{00B7} \(book.timeLeft)").lineLimit(1)
                    Text("Today: \(minutes) min").lineLimit(1)
                } else {
                    Text("Bookscroll").font(.headline)
                    Text("Open a book to see it here.").lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(alignment: .top, spacing: 12) {
                summary
                if let book, !book.upNext.isEmpty {
                    Text(book.upNext)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(7)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityLabel("Up next: \(book.upNext)")
                }
            }
        default:
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let book {
                Text(book.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                ProgressView(value: Double(book.percent), total: 100)
                    .tint(.accentColor)
                    .accessibilityLabel("\(book.percent) percent read")
                Text("\(book.percent)% \u{00B7} \(book.timeLeft)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Image(systemName: "books.vertical")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("No book in progress")
                    .font(.headline)
                Spacer(minLength: 2)
            }
            Text(streak > 0 ? "Today \(minutes) min \u{00B7} \(streak) d streak" : "Today \(minutes) min")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: Live Activity

struct ReadingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReadingActivityAttributes.self) { context in
            ReadingActivityView(attributes: context.attributes, state: context.state)
                .padding(16)
                .widgetURL(AppLink.book(context.attributes.bookID).url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "book")
                        .font(.title2)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.percent)%")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(context.state.percent), total: 100)
                            .accessibilityLabel("\(context.state.percent) percent read")
                        Text("\(context.state.timeLeft) \u{00B7} today \(context.state.minutesToday) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "book")
                    .accessibilityLabel(context.attributes.title)
            } compactTrailing: {
                Text("\(context.state.percent)%")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "book")
                    .accessibilityLabel(context.attributes.title)
            }
            .widgetURL(AppLink.book(context.attributes.bookID).url)
        }
    }
}

struct ReadingActivityView: View {
    let attributes: ReadingActivityAttributes
    let state: ReadingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: state.isPaused ? "book.closed" : "book")
                    .accessibilityHidden(true)
                Text(attributes.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(state.percent)%")
                    .font(.headline)
                    .monospacedDigit()
            }
            ProgressView(value: Double(state.percent), total: 100)
                .accessibilityLabel("\(state.percent) percent read")
            Text(state.isPaused
                 ? "Paused \u{00B7} \(state.timeLeft) \u{00B7} today \(state.minutesToday) min \u{00B7} tap to continue"
                 : "\(state.timeLeft) \u{00B7} today \(state.minutesToday) min")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
