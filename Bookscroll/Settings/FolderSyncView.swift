import SwiftUI
import UniformTypeIdentifiers

/// Settings › Synced folder: pick one folder; new book files in it are imported when the app
/// opens or comes back to the front.
@MainActor
struct FolderSyncView: View {
    @Environment(AppModel.self) private var app
    @State private var isPicking = false
    @State private var confirmsStop = false

    private var sync: FolderSync { app.folderSync }

    var body: some View {
        List {
            Section {
                if let name = sync.folderName {
                    LabeledRow(title: "Folder", value: name)
                        .accessibilityIdentifier("folderSync.folder")
                    LabeledRow(title: "Last checked", value: lastCheckedText)
                    Button("Sync Now") { syncNow() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("folderSync.syncNow")
                    Button("Change Folder\u{2026}") { isPicking = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("folderSync.change")
                    Button("Stop Syncing", role: .destructive) { confirmsStop = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("folderSync.stop")
                } else {
                    Button("Choose Folder\u{2026}") { isPicking = true }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("folderSync.choose")
                }
                if let error = sync.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityIdentifier("folderSync.error")
                }
            } footer: {
                Text("Bookscroll imports each new EPUB, PDF, text, Markdown, HTML or RTF file in the folder and its subfolders when you open the app. A file is imported once. Removing a file from the folder does not delete the book, and a book you delete is not imported again. Books already in your library are skipped.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Synced Folder")
        .navigationBarTitleDisplayMode(.inline)
        .themedNavigationBar()
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder]) { result in
            switch result {
            case let .success(folder):
                sync.choose(folder)
            case let .failure(error):
                sync.errorMessage = "The folder could not be opened: \(error.localizedDescription)"
            }
        }
        .confirmationDialog("Stop syncing \u{201C}\(sync.folderName ?? "")\u{201D}?", isPresented: $confirmsStop, titleVisibility: .visible) {
            Button("Stop Syncing", role: .destructive) { sync.stop() }
        } message: {
            Text("Books already imported stay in your library.")
        }
    }

    private var lastCheckedText: String {
        guard let date = sync.lastSync else { return "Never" }
        let when = date.formatted(date: .abbreviated, time: .shortened)
        switch sync.lastSyncCount {
        case 0: return "\(when), no new files"
        case 1: return "\(when), 1 new file"
        default: return "\(when), \(sync.lastSyncCount) new files"
        }
    }

    private func syncNow() {
        if sync.sync() > 0 { app.selectedTab = .library }
    }
}

/// A title with a value, side by side when they fit, else stacked.
@MainActor
private struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Text(title).foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.primaryText)
                Text(value).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
