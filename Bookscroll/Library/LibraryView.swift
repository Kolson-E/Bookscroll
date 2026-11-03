import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            // A new identity re-runs the @Query after a background import has saved.
            BookList()
                .id(app.libraryVersion)
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import", systemImage: "plus")
                        }
                        .accessibilityLabel("Import books")
                        .accessibilityHint("Opens Files to pick EPUB or PDF files")
                    }
                }
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: [.epub, .pdf],
                    allowsMultipleSelection: true
                ) { result in
                    if case let .success(urls) = result {
                        app.importer.enqueue(urls)
                    }
                }
        }
    }
}

private struct BookList: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Book.addedAt, order: .reverse) private var books: [Book]

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
                    Text("Tap + to import DRM-free EPUB or PDF files from Files, iCloud Drive or any file provider. Apple Books purchases are DRM-protected and cannot be imported.")
                }
            }
        }
    }
}

private struct BookRow: View {
    let book: Book

    private var percent: Int { TextUtils.percent(book.positionOffset, of: book.totalCharacters) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(title: book.title, author: book.author, size: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.headline)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(book.format.label)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary, lineWidth: 1))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: book.progress)
            Text("\(percent)% read")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let note = book.importNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(book.title), by \(book.author). \(book.format.label). \(percent) percent read."
        if let note = book.importNote { text += " \(note)" }
        return text
    }
}

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
                    .foregroundStyle(.secondary)
            case .importing:
                ProgressView(value: job.progress)
                Text("Importing \(Int(job.progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
