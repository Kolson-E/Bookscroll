import SwiftData
import UIKit
import XCTest
@testable import Bookscroll

/// A book as the Library sort and filter see it.
private struct Item: LibraryArrangeable {
    var id = UUID()
    var title: String
    var author: String = "Someone"
    var addedAt: Date = Date(timeIntervalSince1970: 0)
    var lastReadAt: Date?
    var finishedAt: Date?
    var positionOffset: Int = 0
    var progress: Double = 0
    var hiddenFromMix = false
    var format: BookFormat = .epub
}

/// Library sort and filter, finished books, details, covers and language detection.
final class LibraryArrangementTests: XCTestCase {
    private func date(_ day: Double) -> Date { Date(timeIntervalSince1970: day * 86_400) }

    func testTitleKeyIgnoresLeadingArticles() {
        XCTAssertEqual(LibraryArrangement.titleKey("The Stone Bridge"), "Stone Bridge")
        XCTAssertEqual(LibraryArrangement.titleKey("  A Tale of Two Cities"), "Tale of Two Cities")
        XCTAssertEqual(LibraryArrangement.titleKey("An Essay"), "Essay")
        XCTAssertEqual(LibraryArrangement.titleKey("Theory of Everything"), "Theory of Everything", "Only whole words")
        XCTAssertEqual(LibraryArrangement.titleKey("The"), "The", "A title that is only an article stays")
    }

    func testAuthorKeyFilesBySurname() {
        XCTAssertEqual(LibraryArrangement.authorKey("Jane Austen"), "Austen Jane")
        XCTAssertEqual(LibraryArrangement.authorKey("Austen, Jane"), "Austen Jane")
        XCTAssertEqual(LibraryArrangement.authorKey("Martin Luther King Jr."), "King Martin Luther")
        XCTAssertEqual(LibraryArrangement.authorKey("Martin Luther King, Jr."), "King Martin Luther")
        XCTAssertEqual(LibraryArrangement.authorKey("Ada Example, Ben Sample"), "Example Ada", "The importer joins authors with commas")
        XCTAssertEqual(LibraryArrangement.authorKey("van Gogh, Vincent"), "van Gogh Vincent")
        XCTAssertEqual(LibraryArrangement.authorKey("Ada Example and Ben Sample"), "Example Ada")
        XCTAssertEqual(LibraryArrangement.authorKey("Homer"), "Homer")
        XCTAssertEqual(LibraryArrangement.authorKey(""), "")
    }

    func testSortOrders() {
        let a = Item(title: "The Zebra", author: "Carol Young", addedAt: date(3), lastReadAt: date(10), progress: 0.2)
        let b = Item(title: "Apple", author: "Ann Zed", addedAt: date(1), lastReadAt: nil, progress: 0)
        let c = Item(title: "mango", author: "Bob Xu", addedAt: date(2), lastReadAt: date(20), progress: 0.9)
        let d = Item(title: "Kiwi", author: "Dan Abel", addedAt: date(4), finishedAt: date(5), positionOffset: 10, progress: 0.1)
        let books = [a, b, c, d]
        func titles(_ sort: LibrarySort) -> [String] { LibraryArrangement.arrange(books, sort: sort).map(\.title) }

        XCTAssertEqual(titles(.recentlyRead), ["mango", "The Zebra", "Kiwi", "Apple"], "Never-read books follow, newest import first")
        XCTAssertEqual(titles(.recentlyAdded), ["Kiwi", "The Zebra", "mango", "Apple"])
        XCTAssertEqual(titles(.title), ["Apple", "Kiwi", "mango", "The Zebra"], "Case and the article are ignored")
        XCTAssertEqual(titles(.author), ["Kiwi", "mango", "The Zebra", "Apple"], "Abel, Xu, Young, Zed")
        XCTAssertEqual(titles(.progress), ["Kiwi", "mango", "The Zebra", "Apple"], "Finished counts as complete")
    }

    func testTiesAreStable() {
        let same = date(1)
        let books = (0..<20).map { _ in Item(id: UUID(), title: "Same", addedAt: same) }
        let first = LibraryArrangement.arrange(books, sort: .recentlyAdded).map(\.id)
        let again = LibraryArrangement.arrange(Array(books.reversed()), sort: .recentlyAdded).map(\.id)
        XCTAssertEqual(first, again, "Equal keys fall back to the id, so the order never depends on input order")
    }

    func testStatusAndFormatFilters() {
        let notStarted = Item(title: "Not started")
        let reading = Item(title: "Reading", positionOffset: 100, progress: 0.3)
        let finished = Item(title: "Finished", finishedAt: date(1), positionOffset: 0, format: .pdf)
        let hidden = Item(title: "Hidden", positionOffset: 5, hiddenFromMix: true, format: .pdf)
        let books = [notStarted, reading, finished, hidden]
        func titles(_ status: LibraryStatusFilter, _ format: LibraryFormatFilter = .all) -> Set<String> {
            Set(LibraryArrangement.arrange(books, sort: .title, status: status, format: format).map(\.title))
        }
        XCTAssertEqual(titles(.all), ["Not started", "Reading", "Finished", "Hidden"])
        XCTAssertEqual(titles(.notStarted), ["Not started"])
        XCTAssertEqual(titles(.reading), ["Reading", "Hidden"])
        XCTAssertEqual(titles(.finished), ["Finished"], "Finished even at position 0")
        XCTAssertEqual(titles(.hidden), ["Hidden"])
        XCTAssertEqual(titles(.all, .pdf), ["Finished", "Hidden"])
        XCTAssertEqual(titles(.all, .epub), ["Not started", "Reading"])
        XCTAssertEqual(titles(.reading, .pdf), ["Hidden"])
        XCTAssertEqual(titles(.finished, .epub), [])
    }

    func testFinishedBooksLeaveMixButNotOneBookMode() {
        let source = InMemorySegmentSource()
        var books: [FeedBook] = []
        for n in 0..<2 {
            let id = UUID()
            let segmented = Segmenter.segment(Fixtures.paragraphs(count: 20, seed: n + 1))
            source.add(bookID: id, segmented: segmented)
            books.append(Fixtures.feedBook(id: id, ordinal: n + 1, title: "Book \(n)", segmented: segmented))
        }
        books[0].finishedAt = .now
        XCTAssertTrue(books[0].isFinished)
        XCTAssertTrue(books[0].isExcludedFromMix(now: .now))
        let mix = FeedEngine(source: source, books: books, style: .paragraph, mode: .mix, seed: 3)
        mix.loadMore(30)
        XCTAssertEqual(Set(mix.posts.map(\.bookID)), [books[1].id])
        let single = FeedEngine(source: source, books: books, style: .paragraph, mode: .single(books[0].id), seed: 3)
        single.loadMore(1)
        XCTAssertEqual(single.posts.first?.bookID, books[0].id)
    }

    // MARK: Language

    func testLanguageDetection() {
        let english = "The river ran fast under the old stone bridge. Nobody in the town could remember when it was built, or by whom. Children threw sticks from one side and raced across to watch them."
        let german = "Der Fluss lief schnell unter der alten Steinbrücke. Niemand in der Stadt konnte sich erinnern, wann sie gebaut wurde oder von wem. Kinder warfen Stöcke von einer Seite."
        let french = "La rivière coulait vite sous le vieux pont de pierre. Personne dans la ville ne se souvenait quand il avait été construit, ni par qui. Les enfants jetaient des bâtons."
        XCTAssertEqual(DerivedData.language(of: english), "en")
        XCTAssertEqual(DerivedData.language(of: german), "de")
        XCTAssertEqual(DerivedData.language(of: french), "fr")
        XCTAssertNil(DerivedData.language(of: ""))
    }

    func testImportStoresTheLanguage() throws {
        let container = try Fixtures.makeContainer()
        let id = try Fixtures.writeBook(title: "English", paragraphs: 30, into: ModelContext(container))
        let book = try XCTUnwrap(LibraryStore(context: ModelContext(container)).book(id: id))
        XCTAssertEqual(book.language, "en")
        XCTAssertEqual(book.derivedVersion, DerivedData.currentVersion)
    }

    func testBackfillComputesTheLanguageOfOlderBooks() throws {
        let container = try Fixtures.makeContainer()
        let context = ModelContext(container)
        let id = try Fixtures.writeBook(title: "Older", paragraphs: 30, into: context)
        let store = LibraryStore(context: context)
        let book = try XCTUnwrap(store.book(id: id))
        book.language = nil
        book.derivedVersion = 1
        try context.save()
        let results = try DerivedDataBackfill.compute(container: container)
        XCTAssertEqual(results.map(\.language), ["en"])
        XCTAssertTrue(store.applyDerived(results))
        XCTAssertEqual(store.book(id: id)?.language, "en")
    }
}

/// Covers and avatar photos on disk.
final class CoverStoreTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try Fixtures.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    static func imageData(width: CGFloat, height: CGFloat, color: UIColor = .systemTeal, png: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return png ? image.pngData()! : image.jpegData(compressionQuality: 0.9)!
    }

    func testSaveScalesDownAndReadsBack() throws {
        let id = UUID()
        XCTAssertFalse(CoverStore.hasImage(bookID: id, photo: false, in: folder))
        XCTAssertNil(CoverStore.imageData(bookID: id, in: folder))

        XCTAssertTrue(CoverStore.save(Self.imageData(width: 1200, height: 1800, png: true), bookID: id, in: folder))
        XCTAssertTrue(CoverStore.hasImage(bookID: id, photo: false, in: folder))
        let stored = try XCTUnwrap(CoverStore.imageData(bookID: id, in: folder))
        let image = try XCTUnwrap(UIImage(data: stored))
        XCTAssertEqual(max(image.size.width * image.scale, image.size.height * image.scale), CGFloat(CoverStore.maximumPixelSize), accuracy: 1)
        XCTAssertEqual(image.size.width / image.size.height, 2.0 / 3.0, accuracy: 0.01, "Aspect ratio kept")
        XCTAssertGreaterThan(CoverStore.totalSize(in: folder), 0)
    }

    func testPhotoWinsOverCoverAndRemoves() throws {
        let id = UUID()
        CoverStore.save(Self.imageData(width: 100, height: 150, color: .red), bookID: id, in: folder)
        CoverStore.save(Self.imageData(width: 200, height: 200, color: .blue), bookID: id, photo: true, in: folder)
        let shown = try XCTUnwrap(CoverStore.imageData(bookID: id, in: folder).flatMap(UIImage.init(data:)))
        XCTAssertEqual(shown.size.width, shown.size.height, accuracy: 1, "The square photo is shown, not the cover")

        CoverStore.remove(bookID: id, photo: true, in: folder)
        let cover = try XCTUnwrap(CoverStore.imageData(bookID: id, in: folder).flatMap(UIImage.init(data:)))
        XCTAssertLessThan(cover.size.width, cover.size.height)

        CoverStore.removeAll(bookID: id, in: folder)
        XCTAssertNil(CoverStore.imageData(bookID: id, in: folder))
        XCTAssertEqual(CoverStore.totalSize(in: folder), 0)
    }

    func testNonImageDataIsRefused() {
        XCTAssertFalse(CoverStore.save(Data("not an image".utf8), bookID: UUID(), in: folder))
        XCTAssertEqual(CoverStore.totalSize(in: folder), 0)
    }

    @MainActor
    func testCacheHonoursHiddenBooksAndInvalidation() throws {
        let cache = CoverCache()
        cache.folder = folder
        let id = UUID()
        XCTAssertNil(cache.image(for: id))
        CoverStore.save(Self.imageData(width: 100, height: 150), bookID: id, in: folder)
        XCTAssertNil(cache.image(for: id), "A miss is remembered until invalidated")
        let before = cache.version
        cache.invalidate(id)
        XCTAssertGreaterThan(cache.version, before)
        XCTAssertNotNil(cache.image(for: id))
        cache.setHidden([id])
        XCTAssertNil(cache.image(for: id), "The reader chose the initial")
        cache.setHidden([])
        XCTAssertNotNil(cache.image(for: id))
    }
}

/// Cover detection in EPUB and PDF files and the import of covers and file facts.
final class CoverImportTests: XCTestCase {
    private func opf(manifest: String, metadata: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title>\(metadata)</metadata>
          <manifest>
            <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
            \(manifest)
          </manifest>
          <spine><itemref idref="c1"/></spine>
        </package>
        """
    }

    func testCoverPathDetection() {
        // EPUB 3: the cover-image property wins over names.
        let epub3 = OPFParser.parse(opf: opf(manifest: """
            <item id="cover" href="Images/cover.jpg" media-type="image/jpeg"/>
            <item id="art" href="Images/front.png" media-type="image/png" properties="cover-image"/>
            """), opfPath: "OEBPS/content.opf")
        XCTAssertEqual(epub3.coverPath, "OEBPS/Images/front.png")

        // EPUB 2: <meta name="cover" content="id">.
        let epub2 = OPFParser.parse(opf: opf(manifest: """
            <item id="cover-file" href="Images/cover.jpg" media-type="image/jpeg"/>
            <item id="img7" href="Images/img7.jpg" media-type="image/jpeg"/>
            """, metadata: #"<meta name="cover" content="img7"/>"#), opfPath: "OEBPS/content.opf")
        XCTAssertEqual(epub2.coverPath, "OEBPS/Images/img7.jpg")

        // Neither: an image named cover.
        let named = OPFParser.parse(opf: opf(manifest: """
            <item id="i1" href="a.jpg" media-type="image/jpeg"/>
            <item id="i2" href="Cover.JPG" media-type="image/jpeg"/>
            """), opfPath: "content.opf")
        XCTAssertEqual(named.coverPath, "Cover.JPG")

        // No image at all, or only images that are not covers.
        XCTAssertNil(OPFParser.parse(opf: EPUBFixture.opf, opfPath: "OEBPS/content.opf").coverPath)
        XCTAssertNil(OPFParser.parse(opf: opf(manifest: #"<item id="i1" href="map.png" media-type="image/png"/>"#), opfPath: "content.opf").coverPath)
    }

    func testEPUBImportStoresTheCoverAndFileFacts() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Harbour Tales.epub")
        let coverOPF = EPUBFixture.opf.replacingOccurrences(
            of: #"<item id="css""#,
            with: #"<item id="cover-image" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/><item id="css""#
        )
        var entries: [(path: String, data: Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(EPUBFixture.container.utf8)),
            ("OEBPS/content.opf", Data(coverOPF.utf8)),
            ("OEBPS/nav.xhtml", Data(EPUBFixture.nav.utf8)),
            ("OEBPS/Text/cover.xhtml", Data(EPUBFixture.cover.utf8)),
            ("OEBPS/Text/chapter 1.xhtml", Data(EPUBFixture.chapterOne.utf8)),
            ("OEBPS/Text/ch2.xhtml", Data(EPUBFixture.chapterTwo.utf8)),
            ("OEBPS/Styles/book.css", Data("p { margin: 0; }".utf8)),
        ]
        entries.append(("OEBPS/Images/cover.jpg", CoverStoreTests.imageData(width: 600, height: 900)))
        try ZipWriter.write(entries: entries, to: url)

        let parsed = try BookImporter.parse(url: url) { _ in }
        XCTAssertNotNil(parsed.cover.flatMap(UIImage.init(data:)))

        let container = try Fixtures.makeContainer()
        let id = try BookImporter.importBook(at: url, into: container)
        defer { CoverStore.removeAll(bookID: id) }
        XCTAssertTrue(CoverStore.hasImage(bookID: id, photo: false))
        let book = try XCTUnwrap(LibraryStore(context: ModelContext(container)).book(id: id))
        XCTAssertEqual(book.sourceFileName, "Harbour Tales.epub")
        let size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        XCTAssertEqual(book.sourceFileSize, size)
        XCTAssertEqual(book.language, "en")
        XCTAssertTrue(book.showsCover)
    }

    func testPDFFirstPageIsTheCover() throws {
        let folder = try Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("sample.pdf")
        try PDFFixture.write(to: url)
        let parsed = try BookImporter.parse(url: url) { _ in }
        let image = try XCTUnwrap(parsed.cover.flatMap(UIImage.init(data:)))
        XCTAssertLessThan(image.size.width, image.size.height, "Portrait page")
    }
}

/// Finished, details and avatars through the app model.
@MainActor
final class LibraryAppTests: XCTestCase {
    private var folder: URL!
    private var savedFolder: URL!

    override func setUp() async throws {
        folder = try Fixtures.temporaryDirectory()
        savedFolder = CoverCache.shared.folder
        CoverCache.shared.folder = folder
        CoverCache.shared.invalidateAll()
    }

    override func tearDown() async throws {
        CoverCache.shared.folder = savedFolder
        CoverCache.shared.setHidden([])
        CoverCache.shared.invalidateAll()
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeApp() async throws -> (AppModel, UUID, UUID) {
        let container = try Fixtures.makeContainer()
        let first = try Fixtures.writeBook(title: "First", paragraphs: 30, seed: 1, into: ModelContext(container))
        let second = try Fixtures.writeBook(title: "Second", paragraphs: 30, seed: 2, into: ModelContext(container))
        let app = AppModel(container: container)
        await app.derivedBackfill?.value
        app.feed.configure(style: .paragraph, mode: .mix)
        return (app, first, second)
    }

    func testMarkAsFinishedLeavesMixAndCanBeUndone() async throws {
        let (app, first, second) = try await makeApp()
        let version = app.libraryVersion
        let now = Date(timeIntervalSince1970: 2_000_000)
        app.setFinished(true, bookID: first, now: now)
        XCTAssertEqual(app.store.book(id: first)?.finishedAt, now)
        XCTAssertGreaterThan(app.libraryVersion, version)
        app.feed.refresh()
        XCTAssertFalse(app.feed.posts.isEmpty)
        XCTAssertTrue(app.feed.posts.allSatisfy { $0.bookID == second })

        app.setFinished(false, bookID: first)
        XCTAssertNil(app.store.book(id: first)?.finishedAt)
        app.feed.refresh()
        app.feed.loadMore()
        XCTAssertTrue(app.feed.posts.contains { $0.bookID == first })
    }

    func testReadingSetsLastReadAt() async throws {
        let (app, first, _) = try await makeApp()
        XCTAssertNil(app.store.book(id: first)?.lastReadAt)
        let before = Date()
        app.store.setPosition(bookID: first, offset: 200)
        let read = try XCTUnwrap(app.store.book(id: first)?.lastReadAt)
        XCTAssertGreaterThanOrEqual(read, before.addingTimeInterval(-1))
        // The same position again is not a new read.
        app.store.updateBook(id: first) { $0.lastReadAt = Date(timeIntervalSince1970: 0) }
        app.store.setPosition(bookID: first, offset: 200)
        XCTAssertEqual(app.store.book(id: first)?.lastReadAt, Date(timeIntervalSince1970: 0))
    }

    func testEditDetailsChangesWhatTheAppShows() async throws {
        let (app, first, _) = try await makeApp()
        app.editDetails(bookID: first, title: "  New Title \n", author: "New Author")
        XCTAssertEqual(app.store.book(id: first)?.title, "New Title")
        XCTAssertEqual(app.store.book(id: first)?.author, "New Author")
        app.feed.configure(style: .paragraph, mode: .single(first))
        app.feed.refresh()
        XCTAssertEqual(app.feed.posts.first?.bookTitle, "New Title")

        // Empty values keep the old ones.
        app.editDetails(bookID: first, title: "   ", author: "")
        XCTAssertEqual(app.store.book(id: first)?.title, "New Title")
        XCTAssertEqual(app.store.book(id: first)?.author, "New Author")
    }

    func testAvatarPhotoAndCoverChoice() async throws {
        let (app, first, second) = try await makeApp()
        XCTAssertNil(CoverCache.shared.image(for: first))

        XCTAssertFalse(app.setAvatarPhoto(bookID: first, data: Data("nope".utf8)))
        XCTAssertTrue(app.setAvatarPhoto(bookID: first, data: CoverStoreTests.imageData(width: 400, height: 400)))
        XCTAssertTrue(CoverStore.hasImage(bookID: first, photo: true, in: folder))
        XCTAssertNotNil(CoverCache.shared.image(for: first))
        XCTAssertNil(CoverCache.shared.image(for: second))

        app.setShowsCover(false, bookID: first)
        XCTAssertEqual(app.store.book(id: first)?.showsCover, false)
        XCTAssertNil(CoverCache.shared.image(for: first), "The initial shows")
        app.setShowsCover(true, bookID: first)
        XCTAssertNotNil(CoverCache.shared.image(for: first))

        app.removeAvatarPhoto(bookID: first)
        XCTAssertFalse(CoverStore.hasImage(bookID: first, photo: true, in: folder))
        XCTAssertNil(CoverCache.shared.image(for: first))
    }

    func testCoverChoiceIsReadAtLaunch() async throws {
        let container = try Fixtures.makeContainer()
        let id = try Fixtures.writeBook(title: "Hidden Cover", paragraphs: 10, into: ModelContext(container))
        CoverStore.save(CoverStoreTests.imageData(width: 100, height: 150), bookID: id, in: folder)
        let context = ModelContext(container)
        try XCTUnwrap(LibraryStore(context: context).book(id: id)).showsCover = false
        try context.save()
        _ = AppModel(container: container)
        XCTAssertNil(CoverCache.shared.image(for: id))
    }

    func testDeletingABookRemovesItsImages() async throws {
        let (app, first, _) = try await makeApp()
        CoverStore.save(CoverStoreTests.imageData(width: 100, height: 150), bookID: first, in: folder)
        app.setAvatarPhoto(bookID: first, data: CoverStoreTests.imageData(width: 100, height: 100))
        await app.deleteBook(id: first)?.value
        XCTAssertFalse(CoverStore.hasImage(bookID: first, photo: false, in: folder))
        XCTAssertFalse(CoverStore.hasImage(bookID: first, photo: true, in: folder))
    }
}

/// Shelves: the store and the shelf feed.
@MainActor
final class ShelfTests: XCTestCase {
    private func makeStore() throws -> (ShelfStore, ModelContainer) {
        let container = try Fixtures.makeContainer()
        return (ShelfStore(context: ModelContext(container)), container)
    }

    func testCreateRenameReorderAndDelete() throws {
        let (shelves, container) = try makeStore()
        XCTAssertNil(shelves.create(name: "   "), "A name is required")
        let a = try XCTUnwrap(shelves.create(name: " Favourites "))
        let b = try XCTUnwrap(shelves.create(name: "favourites"))
        let c = try XCTUnwrap(shelves.create(name: "Poetry"))
        XCTAssertEqual(shelves.shelves.map(\.name), ["Favourites", "favourites 2", "Poetry"], "Names stay unique")

        shelves.rename(c, to: "Favourites")
        XCTAssertEqual(shelves.shelf(id: c)?.name, "Favourites 3")
        shelves.rename(a, to: "Favourites")
        XCTAssertEqual(shelves.shelf(id: a)?.name, "Favourites", "Its own name is not taken")
        shelves.rename(a, to: "")
        XCTAssertEqual(shelves.shelf(id: a)?.name, "Favourites")

        shelves.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(shelves.shelves.map(\.id), [c, a, b])

        // Saved: a new store on the same library reads the same shelves.
        let reopened = ShelfStore(context: ModelContext(container))
        XCTAssertEqual(reopened.shelves.map(\.id), [c, a, b])
        XCTAssertEqual(reopened.shelves.map(\.name), ["Favourites 3", "Favourites", "favourites 2"])

        shelves.delete(a)
        XCTAssertEqual(shelves.shelves.map(\.id), [c, b])
    }

    func testMembership() throws {
        let (shelves, _) = try makeStore()
        let shelf = try XCTUnwrap(shelves.create(name: "Shelf"))
        let books = (0..<4).map { _ in UUID() }

        shelves.add([books[0], books[1], books[0]], to: shelf)
        XCTAssertEqual(shelves.shelf(id: shelf)?.bookIDs, [books[0], books[1]], "No duplicates")
        shelves.add([books[2], books[1]], to: shelf)
        XCTAssertEqual(shelves.shelf(id: shelf)?.bookIDs, [books[0], books[1], books[2]], "Books on the shelf keep their place")

        shelves.toggle(books[1], on: shelf)
        XCTAssertEqual(shelves.shelf(id: shelf)?.bookIDs, [books[0], books[2]])
        shelves.toggle(books[1], on: shelf)
        XCTAssertEqual(shelves.shelf(id: shelf)?.bookIDs, [books[0], books[2], books[1]])

        shelves.moveBooks(on: shelf, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(shelves.shelf(id: shelf)?.bookIDs, [books[1], books[0], books[2]])

        shelves.setMembers([books[3], books[2], books[1]], of: shelf)
        XCTAssertEqual(shelves.shelf(id: shelf)?.bookIDs, [books[1], books[2], books[3]], "Kept books keep their order; new ones go at the end")

        let other = try XCTUnwrap(shelves.create(name: "Other", bookIDs: [books[2]]))
        shelves.removeEverywhere(books[2])
        XCTAssertEqual(shelves.shelf(id: shelf)?.bookIDs, [books[1], books[3]])
        XCTAssertEqual(shelves.shelf(id: other)?.bookIDs, [])
    }

    func testShelfFeedMixesOnlyTheShelfBooksIgnoringMixFilters() {
        let source = InMemorySegmentSource()
        var books: [FeedBook] = []
        for n in 0..<3 {
            let id = UUID()
            let segmented = Segmenter.segment(Fixtures.paragraphs(count: 20, seed: n + 1))
            source.add(bookID: id, segmented: segmented)
            books.append(Fixtures.feedBook(id: id, ordinal: n + 1, title: "Book \(n)", segmented: segmented))
        }
        books[0].hiddenFromMix = true
        books[1].finishedAt = .now
        let selection = ShelfSelection(id: UUID(), name: "Shelf", bookIDs: [books[0].id, books[1].id])
        let engine = FeedEngine(source: source, books: books, style: .paragraph, mode: .shelf(selection), seed: 5)
        engine.loadMore(30)
        XCTAssertEqual(Set(engine.posts.map(\.bookID)), [books[0].id, books[1].id])
        XCTAssertTrue(engine.posts.allSatisfy(\.showsThreadButton), "Interleaved posts link to their thread")
        XCTAssertTrue(engine.posts.allSatisfy { !$0.continuesThread })
        XCTAssertTrue(FeedMode.shelf(selection).interleaves)
        XCTAssertFalse(FeedMode.single(books[0].id).interleaves)
    }

    func testAppShelfFeedAndDeletion() async throws {
        let container = try Fixtures.makeContainer()
        let first = try Fixtures.writeBook(title: "First", paragraphs: 30, seed: 1, into: ModelContext(container))
        let second = try Fixtures.writeBook(title: "Second", paragraphs: 30, seed: 2, into: ModelContext(container))
        let app = AppModel(container: container)
        await app.derivedBackfill?.value
        let shelfID = try XCTUnwrap(app.shelves.create(name: "Only First", bookIDs: [first]))
        let shelf = try XCTUnwrap(app.shelves.shelf(id: shelfID))
        app.feed.configure(style: .paragraph, mode: .shelf(ShelfSelection(id: shelf.id, name: shelf.name, bookIDs: shelf.bookIDs)))
        XCTAssertEqual(app.feed.title, "Only First")
        XCTAssertFalse(app.feed.posts.isEmpty)
        XCTAssertTrue(app.feed.posts.allSatisfy { $0.bookID == first })

        app.shelves.add([second], to: shelfID)
        await app.deleteBook(id: first)?.value
        XCTAssertEqual(app.shelves.shelf(id: shelfID)?.bookIDs, [second], "A deleted book leaves every shelf")
    }
}
