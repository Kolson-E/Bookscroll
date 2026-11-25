import SwiftUI

/// Settings › Storage: the space Bookscroll uses, in total and per book, largest first.
/// Swipe a book to delete it.
@MainActor
struct StorageView: View {
    @Environment(AppModel.self) private var app
    @State private var report: StorageReport?

    var body: some View {
        List {
            Section {
                UsageRow(title: "Total", bytes: report?.total, isTotal: true)
                    .accessibilityIdentifier("storage.total")
                UsageRow(title: "Library", detail: "Book text, marks and reading places", bytes: report?.database)
                UsageRow(title: "Search index", detail: "Rebuilt from the library when needed", bytes: report?.searchIndex)
                UsageRow(title: "Covers, photos and pictures", bytes: report?.covers)
            } header: {
                SectionHeader("On This iPhone")
            } footer: {
                Text("Bookscroll keeps the text of each book, not the original file. The search index is not in device backups.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)

            Section {
                if let report {
                    if report.books.isEmpty {
                        Text("No books.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(report.books) { book in
                        BookUsageRow(book: book)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { report.books[$0].id }
                        self.report?.books.removeAll { ids.contains($0.id) }
                        for id in ids { app.deleteBook(id: id) }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("Measuring")
                }
            } header: {
                SectionHeader("Books")
            } footer: {
                Text("Sizes are estimates: each book gets a share of the library and the search index in proportion to its length. Swipe left on a book to delete it. The space it frees is used again for the next import.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .themedNavigationBar()
        .task(id: app.libraryVersion) {
            report = await app.storageReport()
        }
    }
}

@MainActor
private struct UsageRow: View {
    let title: String
    var detail: String?
    let bytes: Int64?
    var isTotal = false

    private var value: String { bytes.map(StorageReport.format) ?? "\u{2026}" }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                labels
                Spacer(minLength: 8)
                Text(value).foregroundStyle(isTotal ? Theme.primaryText : Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                labels
                Text(value).foregroundStyle(isTotal ? Theme.primaryText : Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fontWeight(isTotal ? .semibold : nil)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title), \($0)" } ?? title)
        .accessibilityValue(value)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Theme.primaryText)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

@MainActor
private struct BookUsageRow: View {
    let book: StorageReport.BookUsage

    private var size: String { "about " + StorageReport.format(book.bytes) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                labels
                Spacer(minLength: 8)
                Text(size).foregroundStyle(Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                labels
                Text(size).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), by \(book.author), \(book.format.label)")
        .accessibilityValue(size)
        .accessibilityIdentifier("storage.book")
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.title)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
            Text("\(book.author) \u{00B7} \(book.format.label)")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
    }
}
