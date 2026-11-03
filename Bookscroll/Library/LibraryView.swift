import SwiftData
import SwiftUI

@MainActor
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    // A new identity re-runs the @Query after a background import has saved.
                    BookList()
                        .id(app.libraryVersion)
                } else {
                    LibrarySearchResults(query: trimmedQuery)
                }
            }
            .searchable(text: $query, prompt: "Titles, authors and text")
            .navigationTitle("Library")
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.presentImporter()
                    } label: {
                        Label("Import", systemImage: "plus")
                    }
                    .accessibilityLabel("Import books")
                    .accessibilityHint("Opens Files to pick EPUB or PDF files")
                    .accessibilityIdentifier("library.import")
                }
            }
        }
    }
}

@MainActor
private struct BookList: View {
    @Environment(AppModel.self) private var app
    @Query(
        filter: #Predicate<Book> { $0.deletionPending == false },
        sort: \Book.addedAt,
        order: .reverse
    ) private var books: [Book]

    var body: some View {
        List {
            if !app.importer.jobs.isEmpty {
                Section("Importing") {
                    ForEach(app.importer.jobs) { job in
                        ImportJobRow(job: job) { app.importer.dismiss(job.id) }
                            .listRowBackground(Theme.background)
                    }
                }
            }
            Section {
                ForEach(books) { book in
                    BookRow(book: book)
                        .listRowBackground(Theme.background)
                        .contextMenu { feedMenu(for: book) }
                }
                .onDelete { offsets in
                    let ids = offsets.map { books[$0].id }
                    for id in ids { app.deleteBook(id: id) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if books.isEmpty && app.importer.jobs.isEmpty {
                ContentUnavailableView {
                    Label("Your library is empty", systemImage: "books.vertical")
                } description: {
                    Text("Import DRM-free EPUB or PDF files from Files, iCloud Drive or any file provider. You can also share a file to Bookscroll from another app. Apple Books purchases are DRM-protected and cannot be imported.")
                        .foregroundStyle(Theme.secondaryText)
                } actions: {
                    Button { app.presentImporter() } label: {
                        Text("Import Books").foregroundStyle(Theme.background)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("Opens Files to pick EPUB or PDF files")
                    .accessibilityIdentifier("library.empty.import")
                }
            }
        }
    }
}

extension BookList {
    /// Mix settings for one book: hide, snooze, weight.
    @ViewBuilder
    func feedMenu(for book: Book) -> some View {
        let id = book.id
        let isSnoozed = (book.snoozedUntil ?? .distantPast) > .now
        Button { app.presentJump(bookID: id) } label: {
            Label("Jump to\u{2026}", systemImage: "list.bullet.indent")
        }
        Section("In Mix") {
            Button { app.setHiddenFromMix(!book.hiddenFromMix, bookID: id) } label: {
                Label(book.hiddenFromMix ? "Show in Mix" : "Hide from Mix", systemImage: book.hiddenFromMix ? "eye" : "eye.slash")
            }
            if isSnoozed {
                Button { app.snooze(bookID: id, days: nil) } label: {
                    Label("End snooze", systemImage: "alarm")
                }
            } else {
                Button { app.snooze(bookID: id, days: 1) } label: {
                    Label("Snooze for a day", systemImage: "moon.zzz")
                }
                Button { app.snooze(bookID: id, days: 7) } label: {
                    Label("Snooze for a week", systemImage: "moon.zzz")
                }
            }
        }
        Section("How often") {
            ForEach(FeedWeightChoice.allCases) { choice in
                Button { app.setFeedWeight(choice.weight, bookID: id) } label: {
                    if choice.matches(book.feedWeight) {
                        Label(choice.title, systemImage: "checkmark")
                    } else {
                        Text(choice.title)
                    }
                }
            }
        }
    }
}

/// The three Mix weights offered in menus.
enum FeedWeightChoice: CaseIterable, Identifiable {
    case less
    case normal
    case more

    var id: Self { self }

    var weight: Double {
        switch self {
        case .less: return 0.5
        case .normal: return 1
        case .more: return 2
        }
    }

    var title: String {
        switch self {
        case .less: return "Less often"
        case .normal: return "Normal"
        case .more: return "More often"
        }
    }

    func matches(_ weight: Double) -> Bool {
        switch self {
        case .less: return weight < 1
        case .normal: return weight == 1
        case .more: return weight > 1
        }
    }
}

@MainActor
private struct BookRow: View {
    let book: Book
    @ScaledMetric(relativeTo: .headline) private var scaledAvatarSize: CGFloat = 40
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var avatarSize: CGFloat { min(scaledAvatarSize, 56) }

    private var percent: Int { TextUtils.percent(book.positionOffset, of: book.totalCharacters) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(title: book.title, author: book.author, size: avatarSize, textStyle: .title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.headline)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    // At accessibility text sizes the badge moves under the author to leave room for the title.
                    if dynamicTypeSize.isAccessibilitySize { formatBadge.padding(.top, 4) }
                }
                Spacer(minLength: 8)
                if !dynamicTypeSize.isAccessibilitySize { formatBadge }
            }
            ProgressView(value: book.progress)
            Text("\(percent)% read")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            if let note = book.importNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let mixStatus {
                Label(mixStatus, systemImage: "shuffle")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var formatBadge: some View {
        Text(book.format.label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.secondaryText, lineWidth: 1))
            .foregroundStyle(Theme.secondaryText)
    }

    /// Hidden, snoozed or weighted in Mix; nil when the book is in Mix as normal.
    private var mixStatus: String? {
        if book.hiddenFromMix { return "Hidden from Mix" }
        if let until = book.snoozedUntil, until > .now {
            return "Snoozed until \(until.formatted(date: .abbreviated, time: .shortened))"
        }
        if book.feedWeight > 1 { return "More often in Mix" }
        if book.feedWeight < 1 { return "Less often in Mix" }
        return nil
    }

    private var accessibilityText: String {
        var text = "\(book.title), by \(book.author). \(book.format.label). \(percent) percent read."
        if let note = book.importNote { text += " \(note)" }
        if let mixStatus { text += " \(mixStatus)." }
        return text
    }
}

@MainActor
private struct ImportJobRow: View {
    let job: ImportManager.Job
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.fileName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                if case .failed = job.status {
                    Button("Dismiss", action: onDismiss)
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Dismiss error for \(job.fileName)")
                }
            }
            switch job.status {
            case .waiting:
                Text("Waiting")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            case .importing:
                ProgressView(value: job.progress)
                Text("Importing \(Int(job.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Library search: books whose title or author matches, then paragraphs that contain the
/// words (full-text index). A paragraph opens the reader there.
@MainActor
private struct LibrarySearchResults: View {
    @Environment(AppModel.self) private var app
    let query: String
    @State private var books: [FeedBook] = []
    @State private var paragraphs: [TextSearchResult] = []
    @State private var searched = false

    var body: some View {
        List {
            if !books.isEmpty {
                Section {
                    ForEach(books) { book in
                        Button {
                            app.presentJump(bookID: book.id)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(title: book.title, author: book.author, size: 32)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(book.title).font(.headline).foregroundStyle(Theme.primaryText)
                                    Text(book.author).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(book.title), by \(book.author)")
                        .accessibilityHint("Opens Jump to for this book")
                        .accessibilityAddTraits(.isButton)
                        .listRowBackground(Theme.background)
                    }
                } header: {
                    Text("Books").foregroundStyle(Theme.secondaryText)
                }
            }
            if !paragraphs.isEmpty {
                Section {
                    ForEach(paragraphs) { result in
                        Button {
                            app.openReader(bookID: result.bookID, charStart: result.charStart, charEnd: result.charEnd)
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.background)
                    }
                } header: {
                    Text("In the text").foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if searched && books.isEmpty && paragraphs.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task(id: "\(query)|\(app.libraryVersion)") {
            // Waits for typing to pause before it searches.
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            books = app.store.feedBooks().filter {
                $0.title.localizedStandardContains(query) || $0.author.localizedStandardContains(query)
            }
            paragraphs = app.searchText(query)
            searched = true
        }
    }
}

@MainActor
private struct SearchResultRow: View {
    let result: TextSearchResult

    private var source: String {
        var parts = [result.bookTitle]
        if !result.chapter.isEmpty { parts.append(result.chapter) }
        parts.append("\(result.percent)%")
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The snippet with the matched words in bold.
    private var snippet: AttributedString {
        var text = AttributedString()
        var bold = false
        var run = ""
        func flush() {
            guard !run.isEmpty else { return }
            var piece = AttributedString(run)
            if bold { piece.inlinePresentationIntent = .stronglyEmphasized }
            text += piece
            run = ""
        }
        for character in result.snippet {
            if character == SearchIndex.markStart {
                flush(); bold = true
            } else if character == SearchIndex.markEnd {
                flush(); bold = false
            } else {
                run.append(character)
            }
        }
        flush()
        return text
    }

    private var plainSnippet: String {
        result.snippet.filter { $0 != SearchIndex.markStart && $0 != SearchIndex.markEnd }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Text(snippet)
                .font(.callout)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(plainSnippet). \(source).")
        .accessibilityHint("Opens the book here")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("search.result")
    }
}
