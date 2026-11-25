import CoreSpotlight
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@main
@MainActor
struct BookscrollApp: App {
    private let container: ModelContainer
    @State private var app: AppModel

    init() {
        let container: ModelContainer
        let searchIndex: SearchIndex?
        let stats: ReadingStats
        // Spotlight, widgets and the Live Activity; off for UI tests, which use a throwaway library.
        var platform = true
        #if DEBUG
        if let testContainer = UITestSupport.makeContainerIfRequested() {
            container = testContainer
            searchIndex = try? SearchIndex.inMemory()
            stats = ReadingStats(fileURL: nil)
            platform = false
        } else {
            container = Self.makeContainer()
            searchIndex = try? SearchIndex(url: SearchIndex.defaultURL)
            stats = ReadingStats()
        }
        #else
        container = Self.makeContainer()
        searchIndex = try? SearchIndex(url: SearchIndex.defaultURL)
        stats = ReadingStats()
        #endif
        FileStaging.removeLeftovers()
        self.container = container
        let app = AppModel(container: container, searchIndex: searchIndex, stats: stats, platform: platform)
        AppModel.current = app
        _app = State(initialValue: app)
    }

    private static func makeContainer() -> ModelContainer {
        // SwiftData stores the library in Application Support, which does not exist on first launch.
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        do {
            return try LibraryContainer.make()
        } catch {
            fatalError("The Bookscroll library could not be opened: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onOpenURL { url in app.handleOpenURL(url) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        app.openSpotlightItem(id)
                    }
                }
        }
        .modelContainer(container)
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
        .sheet(isPresented: $app.isFinderPresented) {
            FindBooksView()
                .environment(app)
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
