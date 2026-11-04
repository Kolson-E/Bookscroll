import Foundation
import Observation
import SwiftData
import UIKit

/// Imports files one after another. Parsing and storing run on a background task;
/// progress and errors are published on the main actor.
@MainActor
@Observable
final class ImportManager {
    struct Job: Identifiable, Equatable {
        enum Status: Equatable {
            case waiting
            case importing
            case failed(String)
        }

        let id = UUID()
        let fileName: String
        var progress: Double = 0
        var status: Status = .waiting

        var isFailed: Bool {
            if case .failed = status { return true }
            return false
        }
    }

    private(set) var jobs: [Job] = []
    @ObservationIgnored var onImported: (() -> Void)?
    /// Called when the queue is empty again.
    @ObservationIgnored var onQueueFinished: (() -> Void)?
    private let container: ModelContainer
    /// What a job imports: a file, or text pasted into the app.
    private enum Source: Sendable {
        case file(URL)
        case pasted(text: String, title: String, author: String)
    }

    @ObservationIgnored private var queue: [(id: UUID, source: Source)] = []
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// True while files are waiting or importing.
    var isBusy: Bool { jobs.contains { !$0.isFailed } }

    init(container: ModelContainer) {
        self.container = container
    }

    func enqueue(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            let job = Job(fileName: url.lastPathComponent)
            jobs.append(job)
            queue.append((job.id, .file(url)))
        }
        start()
    }

    /// Imports pasted text as a book. The job shows the title (or "Pasted text").
    func enqueuePasted(text: String, title: String, author: String) {
        let name = TextUtils.singleLine(title)
        let job = Job(fileName: name.isEmpty ? "Pasted text" : name)
        jobs.append(job)
        queue.append((job.id, .pasted(text: text, title: title, author: author)))
        start()
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        beginBackgroundWork()
        Task { await runQueue() }
    }

    func dismiss(_ id: UUID) {
        jobs.removeAll { $0.id == id && $0.status != .importing }
    }

    private func runQueue() async {
        while !queue.isEmpty {
            let next = queue.removeFirst()
            update(next.id) { $0.status = .importing }
            let container = self.container
            let jobID = next.id
            let source = next.source
            let result: Result<UUID, Error> = await Task.detached(priority: .userInitiated) {
                let progress: (Double) -> Void = { value in
                    Task { @MainActor [weak self] in
                        self?.update(jobID) { $0.progress = value }
                    }
                }
                switch source {
                case let .file(url):
                    // A file handed over by another app is a copy in Documents/Inbox. It is
                    // removed whatever the outcome; the user's original stays where it was.
                    defer { FileStaging.removeIfInboxCopy(url) }
                    do {
                        let staged = try FileStaging.stage(url)
                        defer { FileStaging.cleanUp(staged) }
                        return .success(try BookImporter.importBook(at: staged, into: container, progress: progress))
                    } catch {
                        return .failure(error)
                    }
                case let .pasted(text, title, author):
                    return Result {
                        try BookImporter.importPasted(text: text, title: title, author: author, into: container, progress: progress)
                    }
                }
            }.value

            switch result {
            case .success:
                jobs.removeAll { $0.id == jobID }
                onImported?()
            case let .failure(error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                update(jobID) { $0.status = .failed(message) }
            }
        }
        isRunning = false
        endBackgroundWork()
        onQueueFinished?()
    }

    /// Asks iOS for time to finish when the app goes to the background during an import.
    private func beginBackgroundWork() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Book import") { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundWork() }
        }
    }

    private func endBackgroundWork() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
}

/// Copies a picked file into the app's temporary folder, inside its security scope.
enum FileStaging {
    static func stage(_ url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(stagingPrefix + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readableURL in
                do {
                    try FileManager.default.copyItem(at: readableURL, to: destination)
                } catch {
                    copyError = error
                }
            }
            if let error = coordinationError ?? copyError { throw error }
            return destination
        } catch {
            throw BookImportError.unreadable("The file could not be opened (\(error.localizedDescription)).")
        }
    }

    static let stagingPrefix = "Import-"

    static func cleanUp(_ stagedFile: URL) {
        try? FileManager.default.removeItem(at: stagedFile.deletingLastPathComponent())
    }

    /// Where iOS puts copies of files that other apps send with "Open in".
    static var inboxDirectory: URL {
        URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
    }

    static func isInboxCopy(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let inbox = inboxDirectory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(inbox)
    }

    static func removeIfInboxCopy(_ url: URL) {
        guard isInboxCopy(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes staging folders left by an import that was cut short, and Inbox copies older
    /// than `inboxAge`. Recent Inbox files are kept: one may be the file the app was just
    /// launched to open.
    static func removeLeftovers(inboxAge: TimeInterval = 24 * 60 * 60, now: Date = .now) {
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory
        if let items = try? manager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil) {
            for item in items where item.lastPathComponent.hasPrefix(stagingPrefix) {
                try? manager.removeItem(at: item)
            }
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        if let items = try? manager.contentsOfDirectory(at: inboxDirectory, includingPropertiesForKeys: keys) {
            for item in items {
                let modified = (try? item.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
                if now.timeIntervalSince(modified) > inboxAge {
                    try? manager.removeItem(at: item)
                }
            }
        }
    }
}
