import Foundation
import Observation
import SwiftData

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
    }

    private(set) var jobs: [Job] = []
    @ObservationIgnored var onImported: (() -> Void)?
    private let container: ModelContainer
    @ObservationIgnored private var queue: [(id: UUID, url: URL)] = []
    @ObservationIgnored private var isRunning = false

    init(container: ModelContainer) {
        self.container = container
    }

    func enqueue(_ urls: [URL]) {
        for url in urls {
            let job = Job(fileName: url.lastPathComponent)
            jobs.append(job)
            queue.append((job.id, url))
        }
        guard !isRunning else { return }
        isRunning = true
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
            let url = next.url
            let result: Result<UUID, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let staged = try FileStaging.stage(url)
                    defer { FileStaging.cleanUp(staged) }
                    let id = try BookImporter.importBook(at: staged, into: container) { value in
                        Task { @MainActor [weak self] in
                            self?.update(jobID) { $0.progress = value }
                        }
                    }
                    return .success(id)
                } catch {
                    return .failure(error)
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
            .appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
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

    static func cleanUp(_ stagedFile: URL) {
        try? FileManager.default.removeItem(at: stagedFile.deletingLastPathComponent())
    }
}
