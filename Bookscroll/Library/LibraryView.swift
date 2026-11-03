import SwiftData
import SwiftUI

@MainActor
struct LibraryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            // A new identity re-runs the @Query after a background import has saved.
            BookList()
                .id(app.libraryVersion)
                .navigationTitle("Library")
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

    private var accessibilityText: String {
        var text = "\(book.title), by \(book.author). \(book.format.label). \(percent) percent read."
        if let note = book.importNote { text += " \(note)" }
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
