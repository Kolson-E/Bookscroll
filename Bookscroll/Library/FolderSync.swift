import Foundation
import Observation

/// Finds the book files inside a folder.
enum FolderScan {
    /// Supported book files in `folder` and its subfolders, in path order. Hidden files and
    /// package contents are skipped. An iCloud file that is not downloaded yet is asked to
    /// download and is left for the next scan.
    static func bookFiles(in folder: URL) -> [URL] {
        bookFiles(in: folder, includingNotDownloaded: false).map(\.url)
    }

    /// Supported book files in `folder` and its subfolders, in path order. With
    /// `includingNotDownloaded`, a file still in iCloud is listed too (at the path it will
    /// have), with `isDownloaded` false; a coordinated read downloads it. Either way it is
    /// asked to start downloading.
    static func bookFiles(in folder: URL, includingNotDownloaded: Bool) -> [(url: URL, isDownloaded: Bool)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else { return [] }
        var files: [(url: URL, isDownloaded: Bool)] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if let placeholder = iCloudPlaceholderTarget(name) {
                // ".Book.epub.icloud" stands for "Book.epub", which is still in iCloud.
                if BookFormat.fromExtension((placeholder as NSString).pathExtension) != nil {
                    let target = url.deletingLastPathComponent().appendingPathComponent(placeholder)
                    try? FileManager.default.startDownloadingUbiquitousItem(at: target)
                    if includingNotDownloaded { files.append((target, false)) }
                }
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if name.hasPrefix(".") || values?.isHidden == true {
                if values?.isRegularFile != true { enumerator.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, BookFormat.fromExtension(url.pathExtension) != nil else { continue }
            files.append((url, true))
        }
        return files.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    /// "Book.epub" for ".Book.epub.icloud", else nil.
    static func iCloudPlaceholderTarget(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { return nil }
        let target = String(name.dropFirst().dropLast(".icloud".count))
        return target.isEmpty ? nil : target
    }

    /// The path of `file` inside `folder`, such as "Novels/Book.epub".
    static func relativePath(of file: URL, in folder: URL) -> String {
        let base = folder.standardizedFileURL.resolvingSymlinksInPath().path
        // The parent is resolved, not the file: a file still in iCloud does not exist yet.
        let path = file.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent(file.lastPathComponent).path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : file.lastPathComponent
    }
}

/// Synced folder: Bookscroll imports each new book file that appears in one folder the reader
/// picks (in iCloud Drive, On My iPhone or a file provider). It looks when the app opens or
/// comes back to the front, and on Sync Now.
///
/// - A file is imported once, by its path in the folder. Editing or renaming a file does not
///   import it again under the old path; a new path is a new file.
/// - Deleting a book in Bookscroll does not bring it back; removing a file from the folder
///   does not delete the book.
/// - A file that is already in the library is skipped without an error.
@MainActor
@Observable
final class FolderSync {
    enum Key {
        static let bookmark = "folderSyncBookmark"
        static let name = "folderSyncName"
        static let seen = "folderSyncSeen"
        static let lastSync = "folderSyncLast"
        static let all = [bookmark, name, seen, lastSync]
    }

    private(set) var folderName: String?
    private(set) var lastSync: Date?
    /// Files queued by the last sync.
    private(set) var lastSyncCount = 0
    var errorMessage: String?

    var isOn: Bool { bookmark != nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var bookmark: Data?
    @ObservationIgnored private var seen: Set<String>
    /// Queues files for import. `scope` is the folder whose security scope covers them.
    @ObservationIgnored var enqueue: ([URL], URL) -> Void = { _, _ in }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmark = defaults.data(forKey: Key.bookmark)
        folderName = defaults.string(forKey: Key.name)
        seen = Set(defaults.stringArray(forKey: Key.seen) ?? [])
        lastSync = defaults.object(forKey: Key.lastSync) as? Date
    }

    /// Starts syncing `folder` (from the Files picker) and imports what is in it now.
    func choose(_ folder: URL) {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        do {
            let data = try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            bookmark = data
            folderName = FileManager.default.displayName(atPath: folder.path)
            seen = []
            errorMessage = nil
            save()
        } catch {
            errorMessage = "The folder could not be synced: \(error.localizedDescription)"
            return
        }
        sync()
    }

    /// Stops syncing. Books already imported stay.
    func stop() {
        bookmark = nil
        folderName = nil
        seen = []
        lastSync = nil
        lastSyncCount = 0
        errorMessage = nil
        for key in Key.all { defaults.removeObject(forKey: key) }
    }

    /// Queues the files that have not been imported before. Returns how many.
    @discardableResult
    func sync(now: Date = .now) -> Int {
        guard let folder = resolveFolder() else { return 0 }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        guard (try? folder.checkResourceIsReachable()) == true else {
            errorMessage = "The folder \u{201C}\(folderName ?? folder.lastPathComponent)\u{201D} cannot be found. Choose it again, or stop syncing."
            return 0
        }
        errorMessage = nil
        var new: [URL] = []
        for file in FolderScan.bookFiles(in: folder) {
            let key = FolderScan.relativePath(of: file, in: folder)
            if seen.insert(key).inserted { new.append(file) }
        }
        lastSync = now
        lastSyncCount = new.count
        save()
        if !new.isEmpty { enqueue(new, folder) }
        return new.count
    }

    private func resolveFolder() -> URL? {
        guard let bookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            errorMessage = "The folder cannot be opened any more. Choose it again, or stop syncing."
            return nil
        }
        if isStale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                self.bookmark = fresh
                save()
            }
        }
        return url
    }

    private func save() {
        defaults.set(bookmark, forKey: Key.bookmark)
        defaults.set(folderName, forKey: Key.name)
        defaults.set(seen.sorted(), forKey: Key.seen)
        defaults.set(lastSync, forKey: Key.lastSync)
    }
}
