import CoreSpotlight
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct BookscrollApp: App {
    private let container: ModelContainer
    @State private var app: AppModel
    /// Set when the library on disk could not be opened; the app then shows `LibraryUnavailableView`.
    private let libraryError: String?

    init() {
        let container: ModelContainer
        var searchIndex: SearchIndex?
        var stats: ReadingStats
        var libraryError: String?
        // Spotlight, widgets and the Live Activity; off for UI tests, which use a throwaway library.
        var platform = true
        #if DEBUG
        if let testContainer = UITestSupport.makeContainerIfRequested() {
            container = testContainer
            searchIndex = try? SearchIndex.inMemory()
            stats = ReadingStats(fileURL: nil)
            platform = false
        } else {
            let opened = Self.makeContainer()
            container = opened.0
            libraryError = opened.1
            searchIndex = try? SearchIndex(url: SearchIndex.defaultURL)
            stats = ReadingStats()
        }
        #else
        let opened = Self.makeContainer()
        container = opened.0
        libraryError = opened.1
        searchIndex = try? SearchIndex(url: SearchIndex.defaultURL)
        stats = ReadingStats()
        #endif
        if libraryError != nil {
            // Touch nothing on disk or in the system while the real library is unavailable.
            searchIndex = nil
            stats = ReadingStats(fileURL: nil)
            platform = false
        }
        FileStaging.removeLeftovers()
        self.container = container
        self.libraryError = libraryError
        let app = AppModel(container: container, searchIndex: searchIndex, stats: stats, platform: platform)
        AppModel.current = app
        _app = State(initialValue: app)
    }

    /// Opens the library on disk. If that fails, returns an empty in-memory library and the error,
    /// so the app can explain the problem instead of crashing at launch.
    private static func makeContainer() -> (ModelContainer, String?) {
        // SwiftData stores the library in Application Support, which does not exist on first launch.
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        do {
            return (try LibraryContainer.make(), nil)
        } catch {
            let message = String(describing: error)
            do {
                return (try LibraryContainer.make(inMemory: true), message)
            } catch {
                fatalError("The Bookscroll library could not be opened: \(message)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let libraryError {
                LibraryUnavailableView(details: libraryError)
            } else {
                RootView()
                    .environment(app)
                    .onOpenURL { url in app.handleOpenURL(url) }
                    .onContinueUserActivity(CSSearchableItemActionType) { activity in
                        if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                            app.openSpotlightItem(id)
                        }
                    }
            }
        }
        .modelContainer(container)
    }
}

/// Shown instead of the app when the library on disk cannot be opened (for example a full disk
/// or a damaged store). The files are left as they are, so the next launch can try again.
struct LibraryUnavailableView: View {
    let details: String

    var body: some View {
        ContentUnavailableView {
            Label("Library unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text("Bookscroll could not open your library. Your books have not been deleted. Close Bookscroll, make sure your device has free storage, and open it again.")
                Text(verbatim: details)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .accessibilityIdentifier("library.unavailable")
    }
}

@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var app = app
        let settings = AppSettings.shared
        TabView(selection: $app.selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "text.bubble") }
                .tag(AppModel.Tab.feed)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppModel.Tab.library)
            ShelvesView()
                .tabItem { Label("Shelves", systemImage: "rectangle.stack") }
                .tag(AppModel.Tab.shelves)
            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(AppModel.Tab.saved)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppModel.Tab.settings)
        }
        .tint(Theme.accent)
        .preferredColorScheme(settings.theme.colorScheme)
        .toolbarBackground(Theme.background, for: .tabBar)
        .fileImporter(
            isPresented: $app.isImporterPresented,
            // A folder imports the books inside it.
            allowedContentTypes: BookFormat.importableTypes + [.folder],
            allowsMultipleSelection: true
        ) { result in
            app.handleImporterResult(result)
        }
        .sheet(item: $app.readerRequest) { request in
            ContextReaderView(model: request.model)
                .environment(app)
        }
        .sheet(item: $app.jumpRequest) { request in
            JumpSheet(bookID: request.bookID)
                .environment(app)
        }
        .sheet(item: $app.lookUpPost) { post in
            LookUpSheet(post: post)
        }
        .sheet(item: $app.shareCardRequest) { request in
            ShareCardSheet(content: request.content)
        }
        .sheet(item: $app.shareRequest) { request in
            ActivityView(items: request.items)
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { app.errorMessage != nil },
                set: { if !$0 { app.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(app.errorMessage ?? "") }
        )
        .onDrop(of: BookFormat.importableTypes, delegate: BookDropDelegate(isTargeted: $isDropTargeted) { providers in
            Task {
                let urls = await DroppedFiles.copy(from: providers)
                if !urls.isEmpty { app.importFiles(urls) }
            }
        })
        .overlay {
            if isDropTargeted {
                DropOverlay()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                app.sceneDidBecomeActive()
            } else {
                app.sceneDidLeaveForeground(toBackground: phase == .background)
            }
        }
    }
}
