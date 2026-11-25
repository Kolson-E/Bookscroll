import SwiftUI

/// Choose Books: any set of library books for the feed. Two or more books are mixed like
/// Mix (without Mix's filters); one book is read straight through, as in One book mode.
/// The set can also be kept as a shelf.
@MainActor
struct ChooseFeedBooksSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// The books chosen before.
    let initial: [UUID]
    /// Shows the chosen books in the feed.
    let onChoose: ([UUID]) -> Void
    /// Keeps the chosen books as a new shelf, then shows that shelf.
    var onSaveShelf: (String, [UUID]) -> Void = { _, _ in }
    /// What the chosen books are for.
    var purpose: Purpose = .feed
    /// A short note under a book, such as the reading list set it is in.
    var note: (UUID) -> String? = { _ in nil }

    enum Purpose: Equatable {
        /// The feed's Choose Books.
        case feed
        /// The books of one reading list set; the title is the set's name.
        case readingSet(title: String)
    }

    @State private var selected: Set<UUID> = []
    @State private var query = ""
    @State private var loaded = false
    @State private var isNamingShelf = false
    @State private var shelfName = ""

    private var library: [Book] {
        LibraryArrangement.arrange(app.store.allBooks(), sort: .title)
    }

    private var shown: [Book] {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return library }
        return library.filter { book in
            words.allSatisfy { book.title.localizedStandardContains($0) || book.author.localizedStandardContains($0) }
        }
    }

    /// Chosen ids: the books chosen before keep their order, then new ones in library order.
    private var chosen: [UUID] {
        let kept = initial.filter { selected.contains($0) }
        let keptSet = Set(kept)
        return kept + library.map(\.id).filter { selected.contains($0) && !keptSet.contains($0) }
    }

    private var footerText: LocalizedStringKey {
        switch purpose {
        case .feed:
            return "Two or more books are mixed in one feed; each continues from its own place. One book is read straight through."
        case .readingSet:
            return "The feed mixes the books of a set. The next set starts when every book in this set is finished. A book is in one set only: choosing it here moves it from its old set."
        }
    }

    private var title: String {
        switch purpose {
        case .feed: return String(localized: "Choose Books")
        case let .readingSet(title): return title
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(shown) { book in
                        row(book)
                    }
                } footer: {
                    Text(footerText)
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .searchable(text: $query, prompt: "Search titles and authors")
            .overlay {
                if library.isEmpty {
                    ContentUnavailableView("Your library is empty", systemImage: "books.vertical")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .alert("Save as Shelf", isPresented: $isNamingShelf) {
                TextField("Name", text: $shelfName)
                    .accessibilityIdentifier("choose.shelfName")
                Button("Save") {
                    onSaveShelf(ShelfStore.newShelfName(shelfName), chosen)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The shelf keeps these books, and the feed shows it.")
            }
        }
        .tint(Theme.accent)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            selected = Set(initial)
        }
    }

    private func row(_ book: Book) -> some View {
        let isOn = selected.contains(book.id)
        return Button {
            if isOn { selected.remove(book.id) } else { selected.insert(book.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.accent : Theme.secondaryText)
                VStack(alignment: .leading, spacing: 0) {
                    ShelfBookRow(book: book)
                    if let note = note(book.id) {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.leading, 52)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note(book.id).map { "\(book.title), by \(book.author). \($0)" } ?? "\(book.title), by \(book.author)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("choose.book")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            if !shown.isEmpty {
                let allOn = shown.allSatisfy { selected.contains($0.id) }
                Button(allOn ? "Select None" : "Select All") {
                    if allOn {
                        selected.subtract(shown.map(\.id))
                    } else {
                        selected.formUnion(shown.map(\.id))
                    }
                }
                .accessibilityIdentifier("choose.selectAll")
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !chosen.isEmpty {
            HStack(spacing: 12) {
                if chosen.count > 1 && purpose == .feed {
                    Button {
                        shelfName = ""
                        isNamingShelf = true
                    } label: {
                        Text("Save as Shelf")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("choose.saveShelf")
                }
                Button {
                    onChoose(chosen)
                    dismiss()
                } label: {
                    Group {
                        if case .readingSet = purpose {
                            Text("Save Set (\(chosen.count))")
                        } else if chosen.count == 1 {
                            Text("Read 1 Book")
                        } else {
                            Text("Mix \(chosen.count) Books")
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("choose.done")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.background)
        }
    }
}
