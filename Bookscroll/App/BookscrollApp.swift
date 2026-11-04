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
        #if DEBUG
        if let testContainer = UITestSupport.makeContainerIfRequested() {
            container = testContainer
            searchIndex = try? SearchIndex.inMemory()
        } else {
            container = Self.makeContainer()
            searchIndex = try? SearchIndex(url: SearchIndex.defaultURL)
        }
        #else
        container = Self.makeContainer()
        searchIndex = try? SearchIndex(url: SearchIndex.defaultURL)
        #endif
        FileStaging.removeLeftovers()
        self.container = container
        _app = State(initialValue: AppModel(container: container, searchIndex: searchIndex))
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
        }
        .modelContainer(container)
    }
}

@MainActor
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

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
            allowedContentTypes: BookFormat.importableTypes,
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { app.store.save() }
        }
    }
}
