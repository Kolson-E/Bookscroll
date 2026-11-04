import SwiftUI

/// Shelves: the reader's own groups of books. A shelf can be read as its own feed.
@MainActor
struct ShelvesView: View {
    @Environment(AppModel.self) private var app
    @State private var path: [UUID] = []
    @State private var isNaming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(app.shelves.shelves) { shelf in
                    NavigationLink(value: shelf.id) {
                        ShelfRow(shelf: shelf)
                    }
                    .listRowBackground(Theme.background)
                    .accessibilityIdentifier("shelf.row")
                }
                .onDelete { offsets in
                    let ids = offsets.map { app.shelves.shelves[$0].id }
                    for id in ids { app.shelves.delete(id) }
                }
                .onMove { app.shelves.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if app.shelves.shelves.isEmpty {
                    ContentUnavailableView {
                        Label("No shelves", systemImage: "square.stack")
                    } description: {
                        Text("Group books, like \u{201C}Holiday reading\u{201D} or \u{201C}Philosophy\u{201D}. A book can be on more than one shelf, and a shelf can be read as its own feed.")
                            .foregroundStyle(Theme.secondaryText)
                    } actions: {
                        Button { startNaming() } label: {
                            Text("New Shelf").foregroundStyle(Theme.background)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("shelves.empty.new")
                    }
                }
            }
            .navigationTitle("Shelves")
            .themedNavigationBar()
            .navigationDestination(for: UUID.self) { id in
                ShelfDetailView(shelfID: id)
            }
            .toolbar {
                if !app.shelves.shelves.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startNaming() } label: {
                        Label("New Shelf", systemImage: "plus")
                    }
                    .accessibilityIdentifier("shelves.new")
                }
            }
            .alert("New Shelf", isPresented: $isNaming) {
                TextField("Name", text: $newName)
                    .accessibilityIdentifier("shelf.name")
                Button("Create") {
                    if let id = app.shelves.create(name: newName) { path = [id] }
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func startNaming() {
        newName = ""
        isNaming = true
    }
}

/// A shelf in the list: the first covers, the name and the number of books.
@MainActor
private struct ShelfRow: View {
    @Environment(AppModel.self) private var app
    let shelf: ShelfRecord
    @ScaledMetric(relativeTo: .headline) private var scaledSize: CGFloat = 32
    private var size: CGFloat { min(scaledSize, 48) }

    private var books: [Book] {
        shelf.bookIDs.prefix(3).compactMap { app.store.book(id: $0) }
    }

    private var count: Int {
        shelf.bookIDs.filter { app.store.book(id: $0) != nil }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if books.isEmpty {
                    Circle()
                        .fill(Theme.secondaryBackground)
                        .frame(width: size, height: size)
                        .overlay(Image(systemName: "square.stack").foregroundStyle(Theme.secondaryText))
                }
                ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                    AvatarView(title: book.title, author: book.author, size: size, textStyle: .headline, bookID: book.id)
                        .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                        .offset(x: CGFloat(index) * size * 0.55)
                        .zIndex(Double(3 - index))
                }
            }
            .frame(width: size * (1 + 0.55 * 2), alignment: .leading)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(shelf.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("\(count) books")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The books of one shelf, in the reader's order.
@MainActor
struct ShelfDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("feedMode") private var feedModeRaw = "mix"
    @AppStorage("feedShelfID") private var feedShelfID = ""
    let shelfID: UUID
    @State private var isAddingBooks = false
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false
    @State private var newName = ""

    private var shelf: ShelfRecord? { app.shelves.shelf(id: shelfID) }

    private var books: [Book] {
        _ = app.libraryVersion
        return (shelf?.bookIDs ?? []).compactMap { app.store.book(id: $0) }
    }

    var body: some View {
        let books = self.books
        List {
            if !books.isEmpty {
                Button { readInFeed() } label: {
                    Label {
                        Text("Read as Feed")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        Image(systemName: "text.bubble")
                    }
                    .font(.headline)
                }
                .listRowBackground(Theme.background)
                .accessibilityHint("Shows the books of this shelf, mixed, in the feed")
                .accessibilityIdentifier("shelf.readInFeed")
            }
            ForEach(books) { book in
                Button { app.presentJump(bookID: book.id) } label: {
                    ShelfBookRow(book: book)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.background)
                .accessibilityHint("Opens Jump to")
                .contextMenu {
                    Button { app.presentJump(bookID: book.id) } label: {
                        Label("Jump to\u{2026}", systemImage: "list.bullet.indent")
                    }
                    Button(role: .destructive) { app.shelves.remove([book.id], from: shelfID) } label: {
                        Label("Remove from Shelf", systemImage: "minus.circle")
                    }
                }
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { books[$0].id })
                app.shelves.remove(ids, from: shelfID)
            }
            .onMove { app.shelves.moveBooks(on: shelfID, fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("No books on this shelf", systemImage: "books.vertical")
                } description: {
                    Text("Add books from your library.")
                        .foregroundStyle(Theme.secondaryText)
                } actions: {
                    Button { isAddingBooks = true } label: {
                        Text("Add Books").foregroundStyle(Theme.background)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("shelf.empty.add")
                }
            }
        }
        .navigationTitle(shelf?.name ?? "Shelf")
        .navigationBarTitleDisplayMode(.inline)
        .themedNavigationBar()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !books.isEmpty { EditButton() }
                Menu {
                    Button { isAddingBooks = true } label: {
                        Label("Add or Remove Books\u{2026}", systemImage: "checklist")
                    }
                    Button {
                        newName = shelf?.name ?? ""
                        isRenaming = true
                    } label: {
                        Label("Rename\u{2026}", systemImage: "pencil")
                    }
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Label("Delete Shelf", systemImage: "trash")
                    }
                } label: {
                    Label("Shelf actions", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("shelf.actions")
            }
        }
        .sheet(isPresented: $isAddingBooks) {
            ShelfMembersSheet(shelfID: shelfID)
                .environment(app)
        }
        .alert("Rename Shelf", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Rename") { app.shelves.rename(shelfID, to: newName) }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \u{201C}\(shelf?.name ?? "")\u{201D}?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Shelf", role: .destructive) {
                app.shelves.delete(shelfID)
                dismiss()
            }
        } message: {
            Text("The books stay in your library.")
        }
    }

    private func readInFeed() {
        feedShelfID = shelfID.uuidString
        feedModeRaw = "shelf"
        app.selectedTab = .feed
    }
}

/// A book on a shelf: avatar, title, author and progress.
@MainActor
struct ShelfBookRow: View {
    let book: Book
    @ScaledMetric(relativeTo: .headline) private var scaledSize: CGFloat = 40
    private var size: CGFloat { min(scaledSize, 56) }

    private var status: String {
        if book.finishedAt != nil { return "Finished" }
        return "\(TextUtils.percent(book.positionOffset, of: book.totalCharacters))% read"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(title: book.title, author: book.author, size: size, textStyle: .title3, bookID: book.id)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), by \(book.author). \(status).")
    }
}

/// Choose which library books are on a shelf.
@MainActor
struct ShelfMembersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let shelfID: UUID
    @State private var selected: Set<UUID> = []
    @State private var loaded = false

    private var library: [Book] {
        LibraryArrangement.arrange(app.store.allBooks(), sort: .title)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(library) { book in
                    let isOn = selected.contains(book.id)
                    Button {
                        if isOn { selected.remove(book.id) } else { selected.insert(book.id) }
                    } label: {
                        HStack(spacing: 12) {
                            ShelfBookRow(book: book)
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isOn ? Theme.accent : Theme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.background)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(book.title), by \(book.author)")
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("shelf.member")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .overlay {
                if library.isEmpty {
                    ContentUnavailableView("Your library is empty", systemImage: "books.vertical")
                }
            }
            .navigationTitle(app.shelves.shelf(id: shelfID)?.name ?? "Shelf")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let order = library.map(\.id).filter { selected.contains($0) }
                        app.shelves.setMembers(order, of: shelfID)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("shelf.members.done")
                }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            selected = Set(app.shelves.shelf(id: shelfID)?.bookIDs ?? [])
        }
    }
}
