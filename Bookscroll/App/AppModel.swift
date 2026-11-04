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

struct ShareCardRequest: Identifiable {
    let id = UUID()
    let content: ShareCardContent
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

    // MARK: Highlights

    /// Highlights `start..<end`. Highlights it overlaps or touches are merged into one, so a
    /// range is never highlighted twice.
    @discardableResult
    func addHighlight(bookID: UUID, start: Int, end: Int) -> MarkRecord? {
        guard start < end else { return nil }
        let touching = index.overlapping(.highlight, bookID: bookID, start: start - 1, end: end + 1)
        let lower = touching.map(\.charStart).reduce(start, min)
        let upper = touching.map(\.charEnd).reduce(end, max)
        if !touching.isEmpty {
            let ids = touching.map(\.id)
            store.deleteMarks(ids: ids)
            index.remove(ids: Set(ids))
        }
        let mark = store.addMark(kind: .highlight, bookID: bookID, charStart: lower, charEnd: upper)
        if let mark { index.insert(mark) }
        version += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        return mark
    }

    /// Removes every highlight that overlaps `start..<end`.
    func removeHighlights(bookID: UUID, start: Int, end: Int) {
        let ids = index.overlapping(.highlight, bookID: bookID, start: start, end: end).map(\.id)
        guard !ids.isEmpty else { return }
        store.deleteMarks(ids: ids)
        index.remove(ids: Set(ids))
        version += 1
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Highlights inside `start..<end`, as UTF-16 ranges relative to `start`, clipped to it.
    func highlightRanges(bookID: UUID, start: Int, end: Int) -> [NSRange] {
        index.overlapping(.highlight, bookID: bookID, start: start, end: end)
            .sorted { $0.charStart < $1.charStart }
            .map { mark in
                let lower = max(mark.charStart, start)
                let upper = min(mark.charEnd, end)
                return NSRange(location: lower - start, length: upper - lower)
            }
    }

    func highlightRanges(for post: FeedPost) -> [NSRange] {
        highlightRanges(bookID: post.bookID, start: post.segment.charStart, end: post.segment.textEnd)
    }

    /// Highlights the whole post, or removes the highlights in it.
    func toggleHighlight(_ post: FeedPost) {
        let end = post.segment.textEnd
        if index.isMarked(.highlight, bookID: post.bookID, start: post.segment.charStart, end: end) {
            removeHighlights(bookID: post.bookID, start: post.segment.charStart, end: end)
        } else {
            addHighlight(bookID: post.bookID, start: post.segment.charStart, end: end)
        }
    }
}

/// The Saved tab's lists. Bookmarks come first: they are the reader's own feed of saved places.
enum SavedFilter: String, CaseIterable, Identifiable {
    case bookmarked
    case liked
    case highlights

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bookmarked: return "Bookmarks"
        case .liked: return "Likes"
        case .highlights: return "Highlights"
        }
    }

    var kind: MarkKind {
        switch self {
        case .bookmarked: return .bookmark
        case .liked: return .like
        case .highlights: return .highlight
        }
    }
}

/// One highlight for the Saved tab: the exact highlighted text and where it is.
struct HighlightItem: Identifiable, Equatable {
    let mark: MarkRecord
    let bookTitle: String
    let bookAuthor: String
    let chapter: String
    let percent: Int
    let text: String

    var id: UUID { mark.id }
}

/// A Library search result: a paragraph that contains the words.
struct TextSearchResult: Identifiable, Equatable {
    let bookID: UUID
    let bookTitle: String
    let index: Int
    let charStart: Int
    let charEnd: Int
    let chapter: String
    let percent: Int
    /// Text around the match; matched words are marked with `SearchIndex.markStart/markEnd`.
    let snippet: String

    var id: String { "\(bookID.uuidString)|\(index)" }
}

@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case feed
        case library
        case shelves
        case saved
        case settings
    }

    var selectedTab: Tab = .feed
    /// Shows the Files picker. The Library toolbar and both empty states set it.
    var isImporterPresented = false
    var readerRequest: ReaderRequest?
    var shareRequest: ShareRequest?
    var jumpRequest: JumpRequest?
    /// Shows the share card sheet (Share as image).
    var shareCardRequest: ShareCardRequest?
    /// Post whose text is shown for "Look up a word".
    var lookUpPost: FeedPost?
    private(set) var libraryVersion = 0
    var errorMessage: String?

    let container: ModelContainer
    let store: LibraryStore
    let marks: MarkStore
    let shelves: ShelfStore
    let feed: FeedViewModel
    let importer: ImportManager
    let folderSync: FolderSync
    /// Full-text index of the library. Nil when it could not be opened; search is then off.
    let searchIndex: SearchIndex?
    @ObservationIgnored private(set) var resumedDeletions: [Task<Void, Never>] = []
    @ObservationIgnored private var searchSync: Task<Void, Never>?

    init(container: ModelContainer, searchIndex: SearchIndex? = nil, folderSync: FolderSync? = nil) {
        self.container = container
        self.searchIndex = searchIndex
        let store = LibraryStore(context: container.mainContext)
        self.store = store
        self.marks = MarkStore(store: store)
        self.shelves = ShelfStore(context: container.mainContext)
        self.feed = FeedViewModel(store: store)
        self.importer = ImportManager(container: container)
        self.folderSync = folderSync ?? FolderSync()
        importer.onImported = { [weak self] in
            self?.libraryDidChange()
        }
        importer.coverFolder = CoverCache.shared.folder
        importer.onReplaced = { [weak self] old, new in
            self?.bookWasReplaced(old, by: new)
        }
        // Synced files import quietly: their progress shows in the Library if it is open.
        self.folderSync.enqueue = { [weak importer = self.importer] urls, folder in
            importer?.enqueue(urls, scope: folder, skipsDuplicates: true)
        }
        // Finish deletions that were cut short when the app last stopped.
        resumedDeletions = BookDeleter.pendingBookIDs(in: container.mainContext).map { runDeletion(of: $0) }
        // Index books from before the index existed, or after its file was lost.
        syncSearchIndex()
        derivedBackfill = runDerivedBackfill()
        refreshCoverChoices()
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

    // MARK: Book details

    /// Marks the book as finished (it leaves Mix) or as not finished.
    func setFinished(_ finished: Bool, bookID: UUID, now: Date = .now) {
        store.updateBook(id: bookID) { $0.finishedAt = finished ? now : nil }
        store.save()
        feedSettingsChanged()
    }

    /// Changes the title and author the app shows. Empty values keep the old ones.
    func editDetails(bookID: UUID, title: String, author: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateBook(id: bookID) { book in
            if !title.isEmpty { book.title = title }
            if !author.isEmpty { book.author = author }
        }
        store.save()
        libraryDidChange()
    }

    /// Uses a photo (any image data) as the book's avatar. Returns false when it is not an image.
    @discardableResult
    func setAvatarPhoto(bookID: UUID, data: Data) -> Bool {
        guard CoverStore.save(data, bookID: bookID, photo: true, in: CoverCache.shared.folder) else { return false }
        CoverCache.shared.invalidate(bookID)
        libraryVersion += 1
        return true
    }

    /// Removes the reader's photo; the cover (or the initial) shows again.
    func removeAvatarPhoto(bookID: UUID) {
        CoverStore.remove(bookID: bookID, photo: true, in: CoverCache.shared.folder)
        CoverCache.shared.invalidate(bookID)
        libraryVersion += 1
    }

    /// False shows the initial on its colour instead of the cover or photo.
    func setShowsCover(_ shows: Bool, bookID: UUID) {
        store.updateBook(id: bookID) { $0.showsCover = shows }
        store.save()
        refreshCoverChoices()
        libraryVersion += 1
    }

    /// Tells the avatar cache which books show their initial by choice.
    private func refreshCoverChoices() {
        let hidden = Set(store.allBooks().filter { !$0.showsCover }.map(\.id))
        CoverCache.shared.setHidden(hidden)
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

    /// Imports `url` as a new version of the book; the Library shows its progress.
    func replaceFile(of bookID: UUID, with url: URL) {
        selectedTab = .library
        importer.enqueueReplacement(url, for: bookID)
    }

    /// The new version takes the old one's shelves and One book selection; the old one goes.
    private func bookWasReplaced(_ old: UUID, by new: UUID) {
        shelves.replaceEverywhere(old, with: new)
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "singleBookID") == old.uuidString {
            defaults.set(new.uuidString, forKey: "singleBookID")
        }
        deleteBook(id: old)
    }

    /// Queues files and shows the Library, where their progress and errors appear. A folder
    /// queues the book files inside it and its subfolders; books already in the library are
    /// skipped without an error.
    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        selectedTab = .library
        var files: [URL] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let found = isFolder ? FolderScan.bookFiles(in: url) : []
            if accessing { url.stopAccessingSecurityScopedResource() }
            guard isFolder else {
                files.append(url)
                continue
            }
            if found.isEmpty {
                errorMessage = "The folder \u{201C}\(url.lastPathComponent)\u{201D} has no EPUB, PDF, text, Markdown, HTML or RTF files."
            }
            importer.enqueue(found, scope: url, skipsDuplicates: true)
        }
        importer.enqueue(files)
    }

    func libraryDidChange() {
        libraryVersion += 1
        feed.reloadBooks()
        marks.reload()
        refreshCoverChoices()
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
            shelves.removeEverywhere(id)
            CoverStore.removeAll(bookID: id, in: CoverCache.shared.folder)
            CoverCache.shared.invalidate(id)
            libraryDidChange()
        }
    }

    // MARK: Backup

    /// A backup of every book's reading state and the shelves, as JSON.
    func makeBackup(now: Date = .now) async throws -> Data {
        store.save()
        let ids = store.allBooks().map(\.id)
        let shelfList = shelves.shelves
        let container = self.container
        let folder = CoverCache.shared.folder
        return try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            var states: [BookState] = []
            var indexByID: [UUID: Int] = [:]
            for id in ids {
                guard let state = try ReadingStateIO.capture(bookID: id, in: context, photoFolder: folder) else { continue }
                indexByID[id] = states.count
                states.append(state)
            }
            let shelves = shelfList.map { shelf in
                LibraryBackup.ShelfBackup(name: shelf.name, books: shelf.bookIDs.compactMap { indexByID[$0] })
            }
            return try LibraryBackup(createdAt: now, books: states, shelves: shelves).encoded()
        }.value
    }

    /// Restores a backup file picked in Files.
    func restoreBackup(from url: URL) async throws -> RestoreSummary {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BookImportError.unreadable("The file could not be opened.")
        }
        return try await restore(try LibraryBackup.decode(data))
    }

    /// Puts each backed-up book's state on the matching library book (see
    /// `LibraryBackup.match`): place, finish, Mix settings, details, photo; marks it does not
    /// have yet are added. Shelves are made, or books are added to a shelf of the same name.
    func restore(_ backup: LibraryBackup) async throws -> RestoreSummary {
        store.save()
        let library = store.allBooks().map {
            LibraryBackup.LibraryBook(id: $0.id, title: $0.title, author: $0.author, format: $0.formatRaw, totalCharacters: $0.totalCharacters)
        }
        let matches = LibraryBackup.match(backup.books, to: library)
        let states = backup.books
        let container = self.container
        // Finding the places reads every book's text: off the main thread.
        let resolved: [(index: Int, id: UUID, resolved: ReadingStateIO.Resolved)] = try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            var output: [(index: Int, id: UUID, resolved: ReadingStateIO.Resolved)] = []
            for (index, match) in matches.enumerated() {
                guard let id = match else { continue }
                var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
                descriptor.fetchLimit = 1
                guard let book = try context.fetch(descriptor).first else { continue }
                let text = try ReadingStateIO.fullText(of: book, in: context)
                output.append((index, id, ReadingStateIO.resolve(states[index], in: text)))
            }
            return output
        }.value

        // Written on the main context, so the books the app holds show the new values.
        let folder = CoverCache.shared.folder
        for item in resolved {
            guard let book = store.book(id: item.id) else { continue }
            try ReadingStateIO.write(states[item.index], resolved: item.resolved, to: book, in: container.mainContext, options: .details, photoFolder: folder)
            if states[item.index].photo != nil { CoverCache.shared.invalidate(item.id) }
        }
        var shelfCount = 0
        for shelf in backup.shelves {
            let ids = shelf.books.compactMap { $0 >= 0 && $0 < matches.count ? matches[$0] : nil }
            if let existing = shelves.shelves.first(where: { $0.name.caseInsensitiveCompare(shelf.name) == .orderedSame }) {
                shelves.add(ids, to: existing.id)
            } else {
                shelves.create(name: shelf.name, bookIDs: ids)
            }
            shelfCount += 1
        }
        libraryDidChange()
        let missing = zip(backup.books, matches).filter { $0.1 == nil }.map(\.0.title)
        return RestoreSummary(restored: resolved.count, missing: missing, shelves: shelfCount)
    }

    // MARK: Storage

    /// Where the library, the search index and the covers are kept.
    var storageLocations: StorageReport.Locations {
        let configuration = container.configurations.first
        let database = configuration.flatMap { $0.isStoredInMemoryOnly ? nil : $0.url }
        return StorageReport.Locations(database: database, searchIndex: searchIndex?.fileURL, covers: CoverCache.shared.folder)
    }

    /// Measures the space the app uses, off the main thread.
    func storageReport() async -> StorageReport {
        let books = store.storageFacts()
        let locations = storageLocations
        return await Task.detached(priority: .userInitiated) {
            StorageReport.measure(books: books, at: locations)
        }.value
    }

    func openReader(for post: FeedPost) {
        openReader(bookID: post.bookID, charStart: post.segment.charStart, charEnd: post.segment.charEnd)
    }

    /// Opens the reader around `charStart..<charEnd` (a post, a highlight or a search result).
    func openReader(bookID: UUID, charStart: Int, charEnd: Int) {
        guard let book = store.feedBook(id: bookID) else { return }
        let model = ContextReaderModel(
            store: store,
            book: book,
            charStart: charStart,
            charEnd: charEnd
        )
        readerRequest = ReaderRequest(model: model)
    }

    /// Opens the book in One book mode at `offset` (Jump to: start, percent, chapter).
    func jump(bookID: UUID, offset: Int) {
        readerRequest = nil
        jumpRequest = nil
        let defaults = UserDefaults.standard
        defaults.set("single", forKey: "feedMode")
        defaults.set(bookID.uuidString, forKey: "singleBookID")
        feed.configure(style: feed.style, mode: .single(bookID), wordLimit: feed.wordLimit)
        feed.jump(bookID: bookID, offset: offset)
        selectedTab = .feed
    }

    func presentJump(bookID: UUID) {
        readerRequest = nil
        shareRequest = nil
        jumpRequest = JumpRequest(bookID: bookID)
    }

    /// The paragraphs around a post, for the long-press preview.
    func peek(for post: FeedPost) -> PeekContent? {
        guard let book = store.feedBook(id: post.bookID) else { return nil }
        let covered = store.segmentsOverlapping(start: post.segment.charStart, end: post.segment.charEnd, book: book, style: .paragraph, limit: 8)
        guard let first = covered.first, let last = covered.last else { return nil }
        return PeekContent(
            bookTitle: post.bookTitle,
            progressLine: post.progressLine,
            before: store.segments(book: book, style: .paragraph, before: first.index, limit: 2),
            post: covered,
            after: store.segments(book: book, style: .paragraph, from: last.index + 1, limit: 2),
            highlight: post.segment.charStart..<post.segment.charEnd
        )
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
            setWeight: { [weak self] weight in self?.setFeedWeight(weight, bookID: bookID) },
            peek: { [weak self] in self?.peek(for: post) },
            lookUp: { [weak self] in self?.lookUpPost = post },
            continueHere: { [weak self] in self?.continueInFeed(bookID: bookID, offset: post.segment.charStart) },
            highlight: { [weak self] in self?.marks.toggleHighlight(post) }
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

    /// Opens the share card sheet: the post as an image, in a style the reader picks.
    func shareImage(_ post: FeedPost) {
        readerRequest = nil
        shareCardRequest = ShareCardRequest(content: ShareCardContent(post))
    }

    func shareImage(_ item: HighlightItem) {
        shareCardRequest = ShareCardRequest(content: ShareCardContent(
            text: item.text, title: item.bookTitle, author: item.bookAuthor, chapter: item.chapter, percent: item.percent,
            bookID: item.mark.bookID
        ))
    }

    /// Posts for the Saved tab, newest mark first, in the current post style.
    func savedPosts(filter: SavedFilter, style: PostStyle) -> [FeedPost] {
        let books = Dictionary(uniqueKeysWithValues: store.feedBooks().map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [FeedPost] = []
        for mark in marks.index.all where mark.kind == filter.kind {
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

    /// Highlights for the Saved tab, newest first, with the exact highlighted text.
    func highlights() -> [HighlightItem] {
        let books = Dictionary(uniqueKeysWithValues: store.feedBooks().map { ($0.id, $0) })
        var result: [HighlightItem] = []
        for mark in marks.index.all where mark.kind == .highlight {
            guard let book = books[mark.bookID] else { continue }
            let paragraphs = store.segmentsOverlapping(start: mark.charStart, end: mark.charEnd, book: book, style: .paragraph)
            let pieces = paragraphs.compactMap { paragraph -> String? in
                let text = paragraph.text as NSString
                let lower = max(mark.charStart, paragraph.charStart) - paragraph.charStart
                let upper = min(mark.charEnd, paragraph.textEnd) - paragraph.charStart
                guard lower < upper else { return nil }
                let piece = text.substring(with: NSRange(location: lower, length: upper - lower))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return piece.isEmpty ? nil : piece
            }
            guard !pieces.isEmpty else { continue }
            result.append(HighlightItem(
                mark: mark,
                bookTitle: book.title,
                bookAuthor: book.author,
                chapter: paragraphs.first?.chapter ?? "",
                percent: TextUtils.percent(mark.charStart, of: book.totalCharacters),
                text: pieces.joined(separator: "\n\n")
            ))
        }
        return result
    }

    func copyHighlight(_ item: HighlightItem) {
        UIPasteboard.general.string = ShareFormatter.citation(
            text: item.text, title: item.bookTitle, author: item.bookAuthor, chapter: item.chapter, percent: item.percent
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Copied")
    }

    // MARK: Search

    /// Paragraphs in any book that contain every word of `query`, best matches first.
    func searchText(_ query: String, limit: Int = 50) -> [TextSearchResult] {
        guard let searchIndex else { return [] }
        let hits = searchIndex.search(query, limit: limit)
        guard !hits.isEmpty else { return [] }
        let books = Dictionary(uniqueKeysWithValues: store.feedBooks().map { ($0.id, $0) })
        return hits.compactMap { hit in
            guard let book = books[hit.bookID],
                  let paragraph = store.segments(book: book, style: .paragraph, from: hit.index, limit: 1).first,
                  paragraph.index == hit.index else { return nil }
            return TextSearchResult(
                bookID: book.id,
                bookTitle: book.title,
                index: hit.index,
                charStart: paragraph.charStart,
                charEnd: paragraph.charEnd,
                chapter: paragraph.chapter,
                percent: TextUtils.percent(paragraph.charStart, of: book.totalCharacters),
                snippet: hit.snippet
            )
        }
    }
}
