import SwiftData
import SwiftUI

@main
struct BookscrollApp: App {
    private let container: ModelContainer
    @State private var app: AppModel

    init() {
        // SwiftData stores the library in Application Support, which does not exist on first launch.
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Book.self, Segment.self, Mark.self)
        } catch {
            fatalError("The Bookscroll library could not be opened: \(error)")
        }
        self.container = container
        _app = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "text.bubble") }
                .tag(AppModel.Tab.feed)
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(AppModel.Tab.library)
            SavedView()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(AppModel.Tab.saved)
        }
        .sheet(item: $app.readerRequest) { request in
            ContextReaderView(model: request.model)
                .environment(app)
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
