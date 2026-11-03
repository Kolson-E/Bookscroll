import Foundation
import Observation
import SwiftData
import UIKit

struct ReaderRequest: Identifiable {
    let id = UUID()
    let model: ContextReaderModel
}

struct ShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
}

@MainActor
@Observable
final class MarkStore {
    private let store: LibraryStore
    private(set) var index = MarkIndex()
    private(set) var version = 0

    init(store: LibraryStore) {
        self.store = store
        reload()
    }

    func reload() {
        index = MarkIndex(store.allMarks())
        version += 1
    }

    func isMarked(_ kind: MarkKind, _ post: FeedPost) -> Bool {
        index.isMarked(kind, bookID: post.bookID, start: post.segment.charStart, end: post.segment.charEnd)
    }

    /// Adds a mark for the post's range, or removes every mark of that kind that overlaps it.
    func toggle(_ kind: MarkKind, _ post: FeedPost) {
        let existing = index.overlapping(kind, bookID: post.bookID, start: post.segment.charStart, end: post.segment.charEnd)
        if existing.isEmpty {
            if let mark = store.addMark(kind: kind, bookID: post.bookID, charStart: post.segment.charStart, charEnd: post.segment.charEnd) {
                index.insert(mark)
            }
        } else {
            let ids = existing.map(\.id)
            store.deleteMarks(ids: ids)
            index.remove(ids: Set(ids))
        }
        version += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

enum SavedFilter: String, CaseIterable, Identifiable {
    case all
    case liked
    case bookmarked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .liked: return "Liked"
        case .bookmarked: return "Bookmarked"
        }
    }

    func includes(_ kind: MarkKind) -> Bool {
        switch self {
        case .all: return true
        case .liked: return kind == .like
        case .bookmarked: return kind == .bookmark
        }
    }
}

@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case feed
        case library
        case saved
    }

    var selectedTab: Tab = .feed
    /// Shows the Files picker. The Library toolbar and both empty states set it.
    var isImporterPresented = false
    var readerRequest: ReaderRequest?
    var shareRequest: ShareRequest?
    private(set) var libraryVersion = 0
    var errorMessage: String?

    let container: ModelContainer
    let store: LibraryStore
    let marks: MarkStore
    let feed: FeedViewModel
    let importer: ImportManager
    @ObservationIgnored private(set) var resumedDeletions: [Task<Void, Never>] = []

    init(container: ModelContainer) {
        self.container = container
        let store = LibraryStore(context: container.mainContext)
        self.store = store
        self.marks = MarkStore(store: store)
        self.feed = FeedViewModel(store: store)
        self.importer = ImportManager(container: container)
        importer.onImported = { [weak self] in
            self?.libraryDidChange()
        }
        // Finish deletions that were cut short when the app last stopped.
        resumedDeletions = BookDeleter.pendingBookIDs(in: container.mainContext).map { runDeletion(of: $0) }
    }

    // MARK: Import

    func presentImporter() {
        readerRequest = nil
        shareRequest = nil
        isImporterPresented = true
    }

    /// Result of the Files picker.
    func handleImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            importFiles(urls)
        case let .failure(error):
            errorMessage = "Files could not be opened: \(error.localizedDescription)"
        }
    }

    /// A file sent to Bookscroll from Files or another app ("Open in", share sheet).
    func handleOpenURL(_ url: URL) {
        guard url.isFileURL else { return }
        readerRequest = nil
        shareRequest = nil
        importFiles([url])
    }

    /// Queues files and shows the Library, where their progress and errors appear.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        selectedTab = .library
        importer.enqueue(urls)
    }

    func libraryDidChange() {
        libraryVersion += 1
        feed.reloadBooks()
        marks.reload()
    }

    /// Hides the book at once (Library, Feed, Saved) and deletes its rows off the main thread.
    /// Returns the background deletion, so callers (tests) can wait for it.
    @discardableResult
    func deleteBook(id: UUID) -> Task<Void, Never>? {
        guard store.book(id: id)?.deletionPending == false else { return nil }
        store.markForDeletion(id: id)
        feed.removeBook(id)
        marks.reload()
        return runDeletion(of: id)
    }

    @discardableResult
    private func runDeletion(of id: UUID) -> Task<Void, Never> {
        let container = self.container
        return Task {
            let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                return Result { try BookDeleter.delete(bookID: id, in: context) }
            }.value
            if case let .failure(error) = result {
                errorMessage = "The book could not be deleted: \(error.localizedDescription)"
            }
            store.forgetBook(id: id)
            libraryDidChange()
        }
    }

    func openReader(for post: FeedPost) {
        guard let book = store.feedBook(id: post.bookID) else { return }
        let model = ContextReaderModel(
            store: store,
            book: book,
            charStart: post.segment.charStart,
            charEnd: post.segment.charEnd
        )
        readerRequest = ReaderRequest(model: model)
    }

    func continueInFeed(bookID: UUID, offset: Int) {
        readerRequest = nil
        feed.jump(bookID: bookID, offset: offset)
        selectedTab = .feed
    }

    func shareText(_ post: FeedPost) {
        shareRequest = ShareRequest(items: [ShareFormatter.quote(post)])
    }

    func shareImage(_ post: FeedPost) {
        if let image = ShareCardRenderer.image(for: post) {
            shareRequest = ShareRequest(items: [image])
        } else {
            shareRequest = ShareRequest(items: [ShareFormatter.quote(post)])
        }
    }

    /// Posts for the Saved tab, newest mark first, in the current post style.
    func savedPosts(filter: SavedFilter, style: PostStyle) -> [FeedPost] {
        let books = Dictionary(uniqueKeysWithValues: store.feedBooks().map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [FeedPost] = []
        for mark in marks.index.all where filter.includes(mark.kind) {
            guard let book = books[mark.bookID] else { continue }
            let segments = store.segmentsOverlapping(
                start: mark.charStart,
                end: mark.charEnd,
                book: book,
                style: book.effectiveStyle(style)
            )
            for segment in segments {
                let post = FeedPost(segment: segment, book: book, showsThreadButton: true)
                if seen.insert(post.id).inserted {
                    result.append(post)
                }
            }
        }
        return result
    }
}
