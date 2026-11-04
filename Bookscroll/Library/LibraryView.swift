import PhotosUI
import SwiftData
import SwiftUI

@MainActor
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @AppStorage("librarySort") private var sort: LibrarySort = .recentlyRead
    @AppStorage("libraryStatus") private var status: LibraryStatusFilter = .all
    @AppStorage("libraryFormat") private var format: LibraryFormatFilter = .all
    /// Lives here, not in the list: the list is rebuilt when the library changes.
    @State private var detailsTarget: DetailsTarget?
    /// The book that goes on a shelf made from its menu.
    @State private var newShelfBookID: UUID?
    @State private var newShelfName = ""

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFiltered: Bool { status != .all || format != .all }

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    // A new identity re-runs the @Query after a background import has saved.
                    BookList(sort: sort, status: $status, format: $format, detailsTarget: $detailsTarget) { bookID in
                        newShelfName = ""
                        newShelfBookID = bookID
                    }
                        .id(app.libraryVersion)
                } else {
                    LibrarySearchResults(query: trimmedQuery)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
            .sheet(item: $detailsTarget) { target in
                BookDetailsSheet(bookID: target.id)
            }
            .alert("New Shelf", isPresented: isNamingShelf) {
                TextField("Name", text: $newShelfName)
                Button("Create") {
                    if let id = newShelfBookID {
                        app.shelves.create(name: newShelfName, bookIDs: [id])
                    }
                }
                .disabled(newShelfName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The book goes on the new shelf.")
            }
            .navigationTitle("Library")
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    arrangeMenu
                }
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

    private var isNamingShelf: Binding<Bool> {
        Binding(
            get: { newShelfBookID != nil },
            set: { if !$0 { newShelfBookID = nil } }
        )
    }

    private var arrangeMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach(LibrarySort.allCases) { item in
                    MenuChoice(title: item.title, symbol: item.symbol, isSelected: sort == item) { sort = item }
                }
            }
            Section("Show") {
                ForEach(LibraryStatusFilter.allCases) { item in
                    MenuChoice(title: item.title, isSelected: status == item) { status = item }
                }
            }
            Section("Format") {
                ForEach(LibraryFormatFilter.allCases) { item in
                    MenuChoice(title: item.title, isSelected: format == item) { format = item }
                }
            }
        } label: {
            Label("Sort and filter", systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Sort and filter")
        .accessibilityValue(arrangeDescription)
        .accessibilityIdentifier("library.arrange")
    }

    private var arrangeDescription: String {
        var parts = ["Sorted by \(sort.title.lowercased())"]
        if status != .all { parts.append(status.title) }
        if format != .all { parts.append(format.title) }
        return parts.joined(separator: ", ")
    }
}

/// Identifies the book whose details sheet is open.
struct DetailsTarget: Identifiable {
    let id: UUID
}

@MainActor
private struct BookList: View {
    @Environment(AppModel.self) private var app
    @Query(
        filter: #Predicate<Book> { $0.deletionPending == false },
        sort: \Book.addedAt,
        order: .reverse
    ) private var allBooks: [Book]
    let sort: LibrarySort
    @Binding var status: LibraryStatusFilter
    @Binding var format: LibraryFormatFilter
    @Binding var detailsTarget: DetailsTarget?
    /// Asks for a shelf name; the book goes on the new shelf.
    let onNewShelf: (UUID) -> Void

    private var books: [Book] {
        LibraryArrangement.arrange(allBooks, sort: sort, status: status, format: format)
    }

    private var isFiltered: Bool { status != .all || format != .all }

    var body: some View {
        let books = self.books
        List {
            if !app.importer.jobs.isEmpty {
                Section {
                    SectionHeader("Importing")
                        .font(.subheadline.weight(.semibold))
                        .listRowBackground(Theme.background)
                    ForEach(app.importer.jobs) { job in
                        ImportJobRow(job: job) { app.importer.dismiss(job.id) }
                            .listRowBackground(Theme.background)
                    }
                }
            }
            if isFiltered && !allBooks.isEmpty {
                FilterSummaryRow(status: status, format: format, shown: books.count, total: allBooks.count) {
                    status = .all
                    format = .all
                }
                .listRowBackground(Theme.background)
            }
            Section {
                ForEach(books) { book in
                    BookRow(book: book)
                        .listRowBackground(Theme.background)
                        .contextMenu { bookMenu(for: book) }
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
            if allBooks.isEmpty && app.importer.jobs.isEmpty {
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
            } else if books.isEmpty && !allBooks.isEmpty {
                ContentUnavailableView {
                    Label("No books match", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No book in your library matches the filter.")
                        .foregroundStyle(Theme.secondaryText)
                } actions: {
                    Button {
                        status = .all
                        format = .all
                    } label: {
                        Text("Show All Books").foregroundStyle(Theme.background)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("library.filter.clear.empty")
                }
            }
        }
    }
}

/// "Showing Finished · PDF, 3 of 12 books" with a button that clears the filter.
@MainActor
private struct FilterSummaryRow: View {
    let status: LibraryStatusFilter
    let format: LibraryFormatFilter
    let shown: Int
    let total: Int
    let onClear: () -> Void

    private var filterText: String {
        let parts = [status == .all ? nil : status.title, format == .all ? nil : format.title].compactMap { $0 }
        return parts.isEmpty ? LibraryStatusFilter.all.title : parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filterText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("\(shown) of \(total) books")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button("Clear", action: onClear)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear filter")
                .accessibilityIdentifier("library.filter.clear")
        }
        .padding(.vertical, 2)
    }
}

extension BookList {
    /// Book actions and Mix settings for one book: hide, snooze, weight.
    @ViewBuilder
    func bookMenu(for book: Book) -> some View {
        let id = book.id
        let isSnoozed = (book.snoozedUntil ?? .distantPast) > .now
        Button { app.presentJump(bookID: id) } label: {
            Label("Jump to\u{2026}", systemImage: "list.bullet.indent")
        }
        Button { app.setFinished(book.finishedAt == nil, bookID: id) } label: {
            if book.finishedAt == nil {
                Label("Mark as Finished", systemImage: "checkmark.circle")
            } else {
                Label("Mark as Not Finished", systemImage: "arrow.uturn.backward.circle")
            }
        }
        Button { detailsTarget = DetailsTarget(id: id) } label: {
            Label("Edit Details\u{2026}", systemImage: "pencil")
        }
        Menu {
            ForEach(app.shelves.shelves) { shelf in
                Button { app.shelves.toggle(id, on: shelf.id) } label: {
                    if shelf.contains(id) {
                        Label(shelf.name, systemImage: "checkmark")
                    } else {
                        Text(shelf.name)
                    }
                }
            }
            Button { onNewShelf(id) } label: {
                Label("New Shelf\u{2026}", systemImage: "plus")
            }
        } label: {
            Label("Add to Shelf", systemImage: "rectangle.stack.badge.plus")
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
                AvatarView(title: book.title, author: book.author, size: avatarSize, textStyle: .title3, bookID: book.id)
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
            ProgressView(value: book.finishedAt == nil ? book.progress : 1)
            if let finishedAt = book.finishedAt {
                Label {
                    Text("Finished \(finishedAt.formatted(date: .abbreviated, time: .omitted))")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text("\(percent)% read")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
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
            .foregroundStyle(Theme.secondaryText)
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 4))
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
        var text = "\(book.title), by \(book.author). \(book.format.label)."
        if let finishedAt = book.finishedAt {
            text += " Finished \(finishedAt.formatted(date: .long, time: .omitted))."
        } else {
            text += " \(percent) percent read."
        }
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
                    // Headers are rows: a plain list draws section headers on a translucent
                    // bar whose colour the theme does not control.
                    SectionHeader("Books")
                        .font(.subheadline.weight(.semibold))
                        .listRowBackground(Theme.background)
                    ForEach(books) { book in
                        Button {
                            app.presentJump(bookID: book.id)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(title: book.title, author: book.author, size: 32, bookID: book.id)
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
                }
            }
            if !paragraphs.isEmpty {
                Section {
                    SectionHeader("In the text")
                        .font(.subheadline.weight(.semibold))
                        .listRowBackground(Theme.background)
                    ForEach(paragraphs) { result in
                        Button {
                            app.openReader(bookID: result.bookID, charStart: result.charStart, charEnd: result.charEnd)
                        } label: {
                            SearchResultRow(result: result)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.background)
                    }
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
