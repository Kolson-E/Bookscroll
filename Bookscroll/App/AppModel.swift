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
        case settings
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
    /// Full-text index of the library. Nil when it could not be opened; search is then off.
    let searchIndex: SearchIndex?
    @ObservationIgnored private(set) var resumedDeletions: [Task<Void, Never>] = []
    @ObservationIgnored private var searchSync: Task<Void, Never>?

    init(container: ModelContainer, searchIndex: SearchIndex? = nil) {
        self.container = container
        self.searchIndex = searchIndex
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
        // Index books from before the index existed, or after its file was lost.
        syncSearchIndex()
        derivedBackfill = runDerivedBackfill()
    }

    // MARK: Derived data

    @ObservationIgnored private(set) var derivedBackfill: Task<Void, Never>?

    /// Computes the word limit and chapter table of books imported before they existed.
    private func runDerivedBackfill() -> Task<Void, Never> {
        let container = self.container
        return Task {
            let results = await Task.detached(priority: .utility) {
                (try? DerivedDataBackfill.compute(container: container)) ?? []
            }.value
            if store.applyDerived(results) {
                feed.reloadBooks()
            }
        }
    }

    // MARK: Feed filters

    /// Leaves the book out of Mix, or brings it back. One book mode still shows it.
    func setHiddenFromMix(_ hidden: Bool, bookID: UUID) {
        store.updateBook(id: bookID) { $0.hiddenFromMix = hidden }
        feedSettingsChanged()
    }

    /// Leaves the book out of Mix for `days` days; nil ends the snooze.
    func snooze(bookID: UUID, days: Int?, now: Date = .now) {
        let until = days.map { now.addingTimeInterval(TimeInterval($0) * 24 * 60 * 60) }
        store.updateBook(id: bookID) { $0.snoozedUntil = until }
        feedSettingsChanged()
    }

    /// How often Mix picks the book: 0.5 less, 1 normal, 2 more.
    func setFeedWeight(_ weight: Double, bookID: UUID) {
        store.updateBook(id: bookID) { $0.feedWeight = weight }
        feedSettingsChanged()
    }

    private func feedSettingsChanged() {
        libraryVersion += 1
        feed.reloadBooks()
    }

    // MARK: Search index

    /// Brings the search index in line with the library, off the main thread: adds books it
    /// does not hold and drops books that are gone. Runs after each change; runs never overlap.
    /// Returns the run, so callers (tests) can wait for it.
    @discardableResult
    func syncSearchIndex() -> Task<Void, Never>? {
        guard let searchIndex else { return nil }
        let previous = searchSync
        let container = self.container
        let run = Task {
            await previous?.value
            await Task.detached(priority: .utility) {
                _ = try? searchIndex.indexMissingBooks(container: container)
            }.value
        }
        searchSync = run
        return run
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
        syncSearchIndex()
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

    /// Everything a post row can do, wired to this model.
    func actions(for post: FeedPost) -> PostActions {
        let bookID = post.bookID
        return PostActions(
            bookFeedWeight: store.feedBook(id: bookID)?.feedWeight ?? 1,
            like: { [weak self] in self?.marks.toggle(.like, post) },
            bookmark: { [weak self] in self?.marks.toggle(.bookmark, post) },
            open: { [weak self] in self?.openReader(for: post) },
            shareText: { [weak self] in self?.shareText(post) },
            shareImage: { [weak self] in self?.shareImage(post) },
            copy: { [weak self] withCitation in self?.copy(post, withCitation: withCitation) },
            hideFromMix: { [weak self] in self?.setHiddenFromMix(true, bookID: bookID) },
            snooze: { [weak self] days in self?.snooze(bookID: bookID, days: days) },
            setWeight: { [weak self] weight in self?.setFeedWeight(weight, bookID: bookID) }
        )
    }

    /// Copies the post text, or the text with title, author, chapter and percent.
    func copy(_ post: FeedPost, withCitation: Bool) {
        UIPasteboard.general.string = withCitation ? ShareFormatter.citation(post) : post.segment.text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Copied")
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
