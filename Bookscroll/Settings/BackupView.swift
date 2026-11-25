import SwiftUI
import UniformTypeIdentifiers

/// Settings › Back Up and Restore: saves the reading state of every book and the shelves as a
/// file, and puts it back on the books in the library.
@MainActor
struct BackupView: View {
    @Environment(AppModel.self) private var app
    @State private var document: BackupDocument?
    @State private var isExporting = false
    @State private var isPickingBackup = false
    @State private var pendingRestore: URL?
    @State private var isWorking = false
    @State private var resultTitle = ""
    @State private var resultMessage: String?
    @State private var exportDate = Date.now

    var body: some View {
        List {
            Section {
                Button("Export Backup\u{2026}") { export() }
                    .frame(minHeight: 44)
                    .disabled(isWorking)
                    .accessibilityIdentifier("backup.export")
                    .fileExporter(
                        isPresented: $isExporting,
                        document: document,
                        contentType: .json,
                        defaultFilename: LibraryBackup.fileName(for: exportDate)
                    ) { result in
                        if case let .failure(error) = result {
                            show("Backup Not Saved", "The backup could not be saved: \(error.localizedDescription)")
                        }
                        document = nil
                    }
            } footer: {
                Text("The backup holds each book\u{2019}s place, finish date, Mix settings, title, author, avatar photo, bookmarks (with their colours) and highlights, your shelves and your reading list. It does not hold the books themselves or your settings.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)

            Section {
                Button("Restore from Backup\u{2026}") { isPickingBackup = true }
                    .frame(minHeight: 44)
                    .disabled(isWorking)
                    .accessibilityIdentifier("backup.restore")
                    .fileImporter(isPresented: $isPickingBackup, allowedContentTypes: [.json]) { result in
                        switch result {
                        case let .success(url): pendingRestore = url
                        case let .failure(error): show("Restore Failed", "The file could not be opened: \(error.localizedDescription)")
                        }
                    }
                if isWorking {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("Working")
                }
            } footer: {
                Text("Import your books first. A restore finds each book by its title, author and length, and puts back its place and details; marks it does not have yet are added.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Back Up and Restore")
        .navigationBarTitleDisplayMode(.inline)
        .themedNavigationBar()
        .confirmationDialog("Restore from this backup?", isPresented: isConfirmingRestore, titleVisibility: .visible, presenting: pendingRestore) { url in
            Button("Restore") { restore(url) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The place, finish date, Mix settings and details of each book in the backup replace the ones in your library.")
        }
        .alert(resultTitle, isPresented: showsResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var isConfirmingRestore: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private var showsResult: Binding<Bool> {
        Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
    }

    private func show(_ title: String, _ message: String) {
        resultTitle = title
        resultMessage = message
    }

    private func export() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                exportDate = .now
                document = BackupDocument(data: try await app.makeBackup(now: exportDate))
                isExporting = true
            } catch {
                show("Backup Failed", "The backup could not be made: \(error.localizedDescription)")
            }
        }
    }

    private func restore(_ url: URL) {
        pendingRestore = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let summary = try await app.restoreBackup(from: url)
                show("Backup Restored", summary.message)
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                show("Restore Failed", message)
            }
        }
    }
}
