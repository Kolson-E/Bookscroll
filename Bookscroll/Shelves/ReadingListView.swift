import SwiftUI

/// The reading list: sets of books in order. The feed (Reading list mode) mixes the books of
/// the current set; the next set starts when every book in it is finished.
@MainActor
struct ReadingListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("feedMode") private var feedModeRaw = "mix"
    @AppStorage(FocusFeed.key) private var focusShelfID = ""

    /// The set whose books are being chosen; nil id is a new set.
    @State private var editing: SetEdit?
    @State private var renaming: ReadingSet?
    @State private var newName = ""
    @State private var deleting: ReadingSet?
    @State private var isConfirmingClear = false

    private struct SetEdit: Identifiable {
        let id = UUID()
        let setID: UUID?
        let title: String
        let initial: [UUID]
    }

    private var sets: [ReadingSet] { app.readingList.sets }

    private var libraryIDs: Set<UUID> {
        _ = app.libraryVersion
        return Set(app.store.allBooks().map(\.id))
    }

    private var finishedIDs: Set<UUID> {
        _ = app.libraryVersion
        return Set(app.store.allBooks().filter { $0.finishedAt != nil }.map(\.id))
    }

    private var statuses: [ReadingSetStatus] {
        ReadingListStore.statuses(of: sets, finished: finishedIDs, library: libraryIDs)
    }

    private var isFeedShowingList: Bool {
        feedModeRaw == FeedModeChoice.readingListTag && focusShelfID.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if sets.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Plan what you read next", systemImage: "list.number")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            Text("Put books in sets, like a playlist. The feed mixes the books of the first set. When every book in it is finished, the next set starts by itself.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }
                let currentStatuses = statuses
                ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                    Section {
                        ForEach(set.bookIDs, id: \.self) { bookID in
                            if let book = app.store.book(id: bookID) {
                                bookRow(book, in: set)
                            }
                        }
                        .onMove { app.readingList.moveBooks(in: set.id, fromOffsets: $0, toOffset: $1) }
                    } header: {
                        header(set, index: index, status: currentStatuses.indices.contains(index) ? currentStatuses[index] : .upNext)
                    }
                    .listRowBackground(Theme.secondaryBackground)
                }
                Section {
                    Button {
                        editing = SetEdit(setID: nil, title: String(localized: "Set \(sets.count + 1)"), initial: [])
                    } label: {
                        Label("Add a Set", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("readingList.addSet")
                } footer: {
                    if !sets.isEmpty {
                        Text("Hold and drag a book to change its order. Swipe a book to mark it finished or take it out. Scrolling past a book's last post in the feed marks it finished.")
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Reading List")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(item: $editing) { edit in
                ChooseFeedBooksSheet(
                    initial: edit.initial,
                    onChoose: { ids in save(ids, for: edit) },
                    purpose: .readingSet(title: edit.title),
                    note: { note(for: $0, editing: edit.setID) }
                )
                .environment(app)
            }
            .alert("Rename Set", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                    .accessibilityIdentifier("readingList.setName")
                Button("Rename") {
                    if let set = renaming { app.readingList.rename(set.id, to: newName) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Leave it empty to call the set by its number.")
            }
            .confirmationDialog(
                "Delete \u{201C}\(deleting.map { app.readingList.displayName(of: $0) } ?? "")\u{201D}?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Set", role: .destructive) {
                    if let set = deleting { app.readingList.delete(set.id) }
                }
            } message: {
                Text("The books stay in your library.")
            }
            .confirmationDialog("Remove the finished sets?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Remove Finished Sets", role: .destructive) {
                    app.readingList.removeDoneSets(finished: finishedIDs, library: libraryIDs)
                }
            } message: {
                Text("Sets whose books are all finished leave the list. The books stay in your library.")
            }
        }
        .tint(Theme.accent)
    }

    private func bookRow(_ book: Book, in set: ReadingSet) -> some View {
        ShelfBookRow(book: book)
            .swipeActions(edge: .leading) {
                if book.finishedAt == nil {
                    Button { app.setFinished(true, bookID: book.id) } label: {
                        Label("Finished", systemImage: "checkmark.circle")
                    }
                    .tint(.green)
                } else {
                    Button { app.setFinished(false, bookID: book.id) } label: {
                        Label("Not Finished", systemImage: "arrow.uturn.backward.circle")
                    }
                    .tint(.orange)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    app.readingList.remove(book.id, from: set.id)
                } label: {
                    Label("Take Out", systemImage: "minus.circle")
                }
            }
            .contextMenu {
                Button {
                    app.setFinished(book.finishedAt == nil, bookID: book.id)
                } label: {
                    if book.finishedAt == nil {
                        Label("Mark as Finished", systemImage: "checkmark.circle")
                    } else {
                        Label("Mark as Not Finished", systemImage: "arrow.uturn.backward.circle")
                    }
                }
                Button(role: .destructive) {
                    app.readingList.remove(book.id, from: set.id)
                } label: {
                    Label("Take Out of the Set", systemImage: "minus.circle")
                }
            }
            .accessibilityIdentifier("readingList.book")
    }

    private func header(_ set: ReadingSet, index: Int, status: ReadingSetStatus) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.readingList.displayName(of: set))
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .textCase(nil)
                Text(statusText(status, set: set))
                    .font(.caption)
                    .foregroundStyle(status == .current ? Theme.accent : Theme.secondaryText)
                    .textCase(nil)
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    editing = SetEdit(setID: set.id, title: app.readingList.displayName(of: set), initial: set.bookIDs)
                } label: {
                    Label("Add or Remove Books", systemImage: "checklist")
                }
                Button {
                    newName = set.name
                    renaming = set
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                if index > 0 {
                    Button { app.readingList.moveSet(set.id, by: -1) } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                }
                if index < sets.count - 1 {
                    Button { app.readingList.moveSet(set.id, by: 1) } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                }
                Divider()
                Button(role: .destructive) { deleting = set } label: {
                    Label("Delete Set", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Set options")
            .accessibilityIdentifier("readingList.setMenu")
        }
        .accessibilityElement(children: .contain)
    }

    private func statusText(_ status: ReadingSetStatus, set: ReadingSet) -> String {
        let inLibrary = set.bookIDs.filter { libraryIDs.contains($0) }
        let finished = inLibrary.filter { finishedIDs.contains($0) }.count
        switch status {
        case .done: return String(localized: "Done \u{00B7} \(inLibrary.count) books")
        case .current: return String(localized: "Reading now \u{00B7} \(finished) of \(inLibrary.count) finished")
        case .upNext: return String(localized: "Up next \u{00B7} \(inLibrary.count) books")
        case .empty: return String(localized: "No books in your library")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .accessibilityIdentifier("readingList.done")
        }
        if !sets.isEmpty {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button { isConfirmingClear = true } label: {
                        Label("Remove Finished Sets", systemImage: "checkmark.circle")
                    }
                    .disabled(!statuses.contains(.done))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !sets.isEmpty && !isFeedShowingList {
            Button {
                focusShelfID = ""
                feedModeRaw = FeedModeChoice.readingListTag
                app.selectedTab = .feed
                dismiss()
            } label: {
                Text("Read in Feed")
                    .font(.headline)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.background)
            .accessibilityIdentifier("readingList.read")
        }
    }

    private func note(for bookID: UUID, editing setID: UUID?) -> String? {
        guard let set = app.readingList.set(containing: bookID), set.id != setID else { return nil }
        return String(localized: "In \(app.readingList.displayName(of: set))")
    }

    private func save(_ ids: [UUID], for edit: SetEdit) {
        if let setID = edit.setID {
            app.readingList.setBooks(ids, of: setID)
        } else {
            app.readingList.addSet(bookIDs: ids)
        }
    }
}
