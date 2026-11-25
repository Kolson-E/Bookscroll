import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A book file found in a folder the reader allowed.
struct FoundBookFile: Identifiable, Hashable, Sendable {
    let url: URL
    /// The allowed folder it is in. Its security scope covers the file.
    let folder: URL
    let folderName: String
    /// The path inside the allowed folder, such as "Novels/Book.epub".
    let relativePath: String
    let format: BookFormat
    /// Nil for a file that is still in iCloud.
    let size: Int64?
    /// False for a file that is still in iCloud: importing it downloads it first.
    let isDownloaded: Bool
    /// A book from a file with the same name is in the library.
    let isInLibrary: Bool

    var id: String { url.standardizedFileURL.path }

    /// The file name without its extension.
    var title: String { (url.lastPathComponent as NSString).deletingPathExtension }

    /// The subfolder inside the allowed folder; empty at the top.
    var subfolder: String { (relativePath as NSString).deletingLastPathComponent }
}

/// Find Books: the book files in the folders the reader allows. iOS lets an app read only
/// the folders the reader picks in Files, so the reader allows a folder once (Downloads,
/// iCloud Drive, On My iPhone or any other) and Bookscroll lists every EPUB, PDF, text,
/// Markdown, HTML and RTF file in it and its subfolders, each time Find Books opens. Nothing
/// is imported until the reader chooses files.
@MainActor
@Observable
final class BookFinder {
    enum Key {
        static let folders = "bookFinderFolders"
        static let all = [folders]
    }

    struct Folder: Identifiable, Equatable, Codable {
        let id: UUID
        var name: String
        var bookmark: Data
    }

    private(set) var folders: [Folder] = []
    private(set) var files: [FoundBookFile] = []
    private(set) var isScanning = false
    /// Set after the first scan, so an empty list can say that nothing was found.
    private(set) var hasScanned = false
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.folders),
           let stored = try? JSONDecoder().decode([Folder].self, from: data) {
            folders = stored
        }
    }

    /// Remembers `folder` (from the Files picker). Returns false when it cannot be kept.
    @discardableResult
    func add(_ folder: URL) -> Bool {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let path = Self.key(for: folder)
        if folders.contains(where: { resolve($0).map(Self.key) == path }) {
            errorMessage = nil
            return true
        }
        do {
            let bookmark = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let name = FileManager.default.displayName(atPath: folder.path)
            folders.append(Folder(id: UUID(), name: name, bookmark: bookmark))
            errorMessage = nil
            save()
            return true
        } catch {
            errorMessage = "The folder could not be added: \(error.localizedDescription)"
            return false
        }
    }

    /// Forgets a folder. Its books stay in the library.
    func remove(_ id: UUID) {
        folders.removeAll { $0.id == id }
        files.removeAll { file in !folders.contains { resolve($0).map(Self.key) == Self.key(for: file.folder) } }
        save()
    }

    /// Looks for book files in every allowed folder. `libraryFileNames`: the file names of
    /// the books in the library, lowercased.
    func scan(libraryFileNames: Set<String>) async {
        guard !isScanning else { return }
        isScanning = true
        var reachable: [(url: URL, name: String)] = []
        var missing: [String] = []
        for folder in folders {
            if let url = resolve(folder) {
                reachable.append((url, folder.name))
            } else {
                missing.append(folder.name)
            }
        }
        let folderList = reachable
        let found = await Task.detached(priority: .userInitiated) {
            Self.findFiles(in: folderList, libraryFileNames: libraryFileNames)
        }.value
        files = found
        isScanning = false
        hasScanned = true
        errorMessage = missing.isEmpty ? nil : "These folders cannot be opened any more: \(missing.joined(separator: ", ")). Remove them and allow them again."
    }

    /// The book files in `folders` and their subfolders, without repeats (a folder inside
    /// another allowed folder lists its files once), in the folders' order, then by path.
    nonisolated static func findFiles(in folders: [(url: URL, name: String)], libraryFileNames: Set<String>) -> [FoundBookFile] {
        var seen = Set<String>()
        var result: [FoundBookFile] = []
        for (folder, name) in folders {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
            for entry in FolderScan.bookFiles(in: folder, includingNotDownloaded: true) {
                let file = entry.url
                guard seen.insert(key(for: file)).inserted,
                      let format = BookFormat.fromExtension(file.pathExtension) else { continue }
                let size = entry.isDownloaded
                    ? (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
                    : nil
                result.append(FoundBookFile(
                    url: file,
                    folder: folder,
                    folderName: name,
                    relativePath: FolderScan.relativePath(of: file, in: folder),
                    format: format,
                    size: size,
                    isDownloaded: entry.isDownloaded,
                    isInLibrary: libraryFileNames.contains(file.lastPathComponent.lowercased())
                ))
            }
        }
        return result
    }

    nonisolated static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func resolve(_ folder: Folder) -> URL? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale, let index = folders.firstIndex(where: { $0.id == folder.id }) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                folders[index].bookmark = fresh
                save()
            }
        }
        return url
    }

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            defaults.set(data, forKey: Key.folders)
        }
    }
}

/// Find Books: every book file in the allowed folders, with a checkbox. Books already in the
/// library are marked and cannot be chosen again.
@MainActor
struct FindBooksView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var isPickingFolder = false

    private var finder: BookFinder { app.bookFinder }

    private var shown: [FoundBookFile] {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return finder.files }
        return finder.files.filter { file in
            words.allSatisfy { file.relativePath.localizedStandardContains($0) }
        }
    }

    /// Shown files that can be chosen (not in the library).
    private var choosable: [FoundBookFile] { shown.filter { !$0.isInLibrary } }

    private var chosen: [FoundBookFile] { finder.files.filter { selected.contains($0.id) } }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Find Books")
                .navigationBarTitleDisplayMode(.inline)
                .themedNavigationBar()
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) { importBar }
        }
        .tint(Theme.accent)
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result, finder.add(url) {
                Task { await rescan() }
            } else if case let .failure(error) = result {
                finder.errorMessage = "The folder could not be opened: \(error.localizedDescription)"
            }
        }
        .task { await rescan() }
    }

    private var list: some View {
        List {
            if let message = finder.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.primaryText)
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            if finder.folders.isEmpty {
                introSection
            } else {
                filesSections
                foldersSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Search file names")
        .refreshable { await rescan() }
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("Find the books on this iPhone", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("iOS lets an app see only the folders you allow. Allow a folder once, for example Downloads, iCloud Drive or On My iPhone, and Bookscroll lists every EPUB, PDF and text file in it and in its folders, each time you open Find Books. Nothing is imported until you choose.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    isPickingFolder = true
                } label: {
                    Label("Allow a Folder", systemImage: "folder.badge.plus")
                        .foregroundStyle(Theme.background)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Opens Files to choose a folder")
                .accessibilityIdentifier("find.allowFolder")
            }
            .padding(.vertical, 6)
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    @ViewBuilder
    private var filesSections: some View {
        if finder.isScanning && finder.files.isEmpty {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for books\u{2026}").foregroundStyle(Theme.secondaryText)
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        } else if finder.hasScanned && shown.isEmpty {
            Section {
                Group {
                    if query.isEmpty {
                        Text("No EPUB, PDF, text, Markdown, HTML or RTF files in these folders.")
                    } else {
                        Text("No file names match \u{201C}\(query)\u{201D}.")
                    }
                }
                .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
        ForEach(groups, id: \.name) { group in
            Section {
                ForEach(group.files) { file in
                    FoundFileRow(file: file, isSelected: selected.contains(file.id)) {
                        toggle(file)
                    }
                }
            } header: {
                Text(verbatim: group.name)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityAddTraits(.isHeader)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    /// Files grouped by allowed folder, in the folders' order.
    private var groups: [(name: String, files: [FoundBookFile])] {
        var order: [String] = []
        var byFolder: [String: [FoundBookFile]] = [:]
        for file in shown {
            if byFolder[file.folderName] == nil { order.append(file.folderName) }
            byFolder[file.folderName, default: []].append(file)
        }
        return order.map { ($0, byFolder[$0] ?? []) }
    }

    private var foldersSection: some View {
        Section {
            ForEach(finder.folders) { folder in
                Label(folder.name, systemImage: "folder")
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityHint("Swipe left to stop looking in this folder")
            }
            .onDelete { offsets in
                let ids = offsets.map { finder.folders[$0].id }
                for id in ids { finder.remove(id) }
                selected = selected.filter { id in finder.files.contains { $0.id == id } }
            }
            Button {
                isPickingFolder = true
            } label: {
                Label("Allow Another Folder", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("find.allowFolder")
        } header: {
            SectionHeader("Folders Bookscroll looks in")
        } footer: {
            Text("Swipe left on a folder to stop looking in it; its books stay in your library. A file still in iCloud downloads when you import it.")
                .foregroundStyle(Theme.secondaryText)
        }
        .listRowBackground(Theme.secondaryBackground)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
                .accessibilityIdentifier("find.close")
        }
        ToolbarItem(placement: .primaryAction) {
            if !choosable.isEmpty {
                let allChosen = choosable.allSatisfy { selected.contains($0.id) }
                Button(allChosen ? "Select None" : "Select All") {
                    if allChosen {
                        selected.subtract(choosable.map(\.id))
                    } else {
                        selected.formUnion(choosable.map(\.id))
                    }
                }
                .accessibilityIdentifier("find.selectAll")
            }
        }
    }

    @ViewBuilder
    private var importBar: some View {
        if !chosen.isEmpty {
            Button {
                app.importFound(chosen)
                dismiss()
            } label: {
                Group {
                    if chosen.count == 1 {
                        Text("Import 1 Book")
                    } else {
                        Text("Import \(chosen.count) Books")
                    }
                }
                    .font(.headline)
                    .foregroundStyle(Theme.background)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.background)
            .accessibilityIdentifier("find.import")
        }
    }

    private func toggle(_ file: FoundBookFile) {
        guard !file.isInLibrary else { return }
        if selected.contains(file.id) { selected.remove(file.id) } else { selected.insert(file.id) }
    }

    private func rescan() async {
        await finder.scan(libraryFileNames: app.libraryFileNames)
        selected = selected.filter { id in finder.files.contains { $0.id == id && !$0.isInLibrary } }
    }
}

/// One found file: a checkbox, its name, format, size and subfolder.
@MainActor
private struct FoundFileRow: View {
    let file: FoundBookFile
    let isSelected: Bool
    let action: () -> Void

    private var details: String {
        var parts = [file.format.label]
        if let size = file.size {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        } else if !file.isDownloaded {
            parts.append(String(localized: "In iCloud"))
        }
        if !file.subfolder.isEmpty { parts.append(file.subfolder) }
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: file.isInLibrary ? "checkmark.seal.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.title3)
                    .foregroundStyle(file.isInLibrary || isSelected ? Theme.accent : Theme.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(file.isInLibrary ? String(localized: "In your library") + " \u{00B7} " + details : details)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(file.isInLibrary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.title)
        .accessibilityValue(file.isInLibrary ? "\(String(localized: "In your library")), \(details)" : details)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("find.file")
    }
}
