import Charts
import SwiftUI

/// Reading Stats (Library toolbar): time and amount read, streak, speed, and time left in the
/// books being read.
@MainActor
struct StatsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stats: ReadingStats { app.stats }

    private struct BookLeft: Identifiable {
        let id: UUID
        let title: String
        let percent: Int
        let seconds: TimeInterval
    }

    private var booksInProgress: [BookLeft] {
        _ = app.libraryVersion
        return app.store.allBooks()
            .filter { $0.finishedAt == nil && $0.positionOffset > 0 }
            .map { book in
                BookLeft(
                    id: book.id,
                    title: book.title,
                    percent: TextUtils.percent(book.positionOffset, of: book.totalCharacters),
                    seconds: stats.timeToRead(characters: book.totalCharacters - book.positionOffset)
                )
            }
            .sorted { $0.seconds < $1.seconds }
    }

    private var finishedThisYear: Int {
        let year = Calendar.current.component(.year, from: .now)
        return app.store.allBooks().filter { book in
            book.finishedAt.map { Calendar.current.component(.year, from: $0) == year } ?? false
        }.count
    }

    private static func words(_ characters: Int) -> String {
        Int((Double(characters) / ReadingStats.charactersPerWord).rounded()).formatted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    tiles
                } header: {
                    SectionHeader("Reading")
                } footer: {
                    Text("Time counts while the feed moves on, with gaps of up to 2 minutes. Words are counted as 6 characters each.")
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    chart
                        .frame(height: 180)
                        .padding(.vertical, 8)
                } header: {
                    SectionHeader("Last 14 days")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    StatRow(title: "Speed", value: "about \(stats.wordsPerMinute) words a minute")
                    StatRow(title: "Total reading time", value: ReadingStats.formatReadingTime(stats.totalSeconds))
                    StatRow(title: "Finished this year", value: finishedThisYear == 1 ? "1 book" : "\(finishedThisYear) books")
                } footer: {
                    Text(stats.measuredCharactersPerMinute == nil
                         ? "Your speed is measured after 10 minutes of reading. Until then, times left use 200 words a minute."
                         : "Times left use your measured speed.")
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    let books = booksInProgress
                    if books.isEmpty {
                        Text("No books in progress.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(books) { book in
                        StatRow(title: book.title, value: "\(book.percent)% \u{00B7} about \(ReadingStats.formatDuration(book.seconds)) left")
                            .accessibilityIdentifier("stats.book")
                    }
                } header: {
                    SectionHeader("Time left")
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Reading Stats")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("stats.done")
                }
            }
        }
        .tint(Theme.accent)
    }

    private var tiles: some View {
        let today = stats.day(.now)
        let week = stats.week()
        let streak = stats.streak()
        let items: [(String, String)] = [
            ("Today", ReadingStats.formatReadingTime(today.seconds)),
            ("Words today", Self.words(today.characters)),
            ("This week", ReadingStats.formatReadingTime(week.seconds)),
            ("Streak", streak == 1 ? "1 day" : "\(streak) days"),
        ]
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            ForEach(0..<((items.count + columns - 1) / columns), id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < items.count {
                            Tile(title: items[index].0, value: items[index].1)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private struct ChartDay: Identifiable {
        let date: Date
        let seconds: Double
        var id: Date { date }
    }

    private var chart: some View {
        let days = stats.lastDays(14).map { ChartDay(date: $0.date, seconds: $0.day.seconds) }
        return Chart(days) { item in
            BarMark(
                x: .value("Day", item.date, unit: .day),
                y: .value("Minutes", item.seconds / 60)
            )
            .foregroundStyle(Theme.accent)
            .accessibilityLabel(item.date.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue(ReadingStats.formatReadingTime(item.seconds))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.secondaryText.opacity(0.3))
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.secondaryText.opacity(0.3))
                AxisValueLabel().foregroundStyle(Theme.secondaryText)
            }
        }
        .chartYAxisLabel("Minutes")
        .accessibilityIdentifier("stats.chart")
    }
}

@MainActor
private struct Tile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(Theme.primaryText).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(Theme.secondaryText).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
