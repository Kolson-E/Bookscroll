import SwiftUI
import UniformTypeIdentifiers

/// Book files dropped on the app (from Files, Finder on a Mac, or another app on iPad).
enum DroppedFiles {
    /// The importable type a provider offers, if any (the first that matches).
    /// Text dragged from a post (no file name) is not a file to import.
    static func bookType(of provider: NSItemProvider, types: [UTType] = BookFormat.importableTypes) -> String? {
        let isFile = provider.suggestedName != nil || provider.registeredTypeIdentifiers.contains(UTType.fileURL.identifier)
        guard isFile else { return nil }
        return provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return types.contains { type.conforms(to: $0) }
        }
    }

    /// Copies each dropped book file to a folder of its own in the temporary folder (the
    /// provider's copy is deleted when its handler returns). Files that fail are left out.
    static func copy(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            guard let type = bookType(of: provider) else { continue }
            if let url = await copy(provider, type: type) { urls.append(url) }
        }
        return urls
    }

    private static func copy(_ provider: NSItemProvider, type: String) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: keepCopy(of: url, suggestedName: provider.suggestedName))
            }
        }
    }

    /// Copies `url` into a new temporary folder, named after the dropped file.
    static func keepCopy(of url: URL, suggestedName: String?) -> URL? {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dropped", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        var name = url.lastPathComponent
        if let suggestedName, !suggestedName.isEmpty, (suggestedName as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty {
            name = suggestedName + "." + url.pathExtension
        } else if let suggestedName, !suggestedName.isEmpty {
            name = suggestedName
        }
        let target = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }
}

/// Shown while book files are dragged over the app.
@MainActor
struct DropOverlay: View {
    var body: some View {
        ZStack {
            Theme.background.opacity(0.85)
            VStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.accent)
                Text("Drop to import")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("EPUB, PDF, text, Markdown, HTML or RTF")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
            .padding(24)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}
