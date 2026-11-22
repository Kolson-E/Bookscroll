import Foundation
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// Book covers and the reader's own avatar photos, as small JPEG files in Application Support
/// (`Covers/<book id>.jpg` and `Covers/<book id>-photo.jpg`). They stay out of the database so
/// the library store stays small. Thread-safe: it only reads and writes files.
enum CoverStore {
    /// Longest side of a stored image, in pixels. An avatar is at most 56 points (168 pixels at 3x).
    static let maximumPixelSize = 360

    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Covers", isDirectory: true)
    }

    static func url(bookID: UUID, photo: Bool, in folder: URL = directory) -> URL {
        folder.appendingPathComponent(bookID.uuidString + (photo ? "-photo" : "") + ".jpg")
    }

    /// Scales `data` (any image format ImageIO reads) down and stores it as JPEG.
    /// Returns false when the data is not an image.
    @discardableResult
    static func save(_ data: Data, bookID: UUID, photo: Bool = false, in folder: URL = directory) -> Bool {
        guard let jpeg = thumbnailJPEG(from: data) else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try jpeg.write(to: url(bookID: bookID, photo: photo, in: folder), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func remove(bookID: UUID, photo: Bool, in folder: URL = directory) {
        try? FileManager.default.removeItem(at: url(bookID: bookID, photo: photo, in: folder))
    }

    static func removeAll(bookID: UUID, in folder: URL = directory) {
        remove(bookID: bookID, photo: false, in: folder)
        remove(bookID: bookID, photo: true, in: folder)
    }

    static func hasImage(bookID: UUID, photo: Bool, in folder: URL = directory) -> Bool {
        FileManager.default.fileExists(atPath: url(bookID: bookID, photo: photo, in: folder).path)
    }

    /// The reader's photo when there is one, else the cover.
    static func imageData(bookID: UUID, in folder: URL = directory) -> Data? {
        (try? Data(contentsOf: url(bookID: bookID, photo: true, in: folder)))
            ?? (try? Data(contentsOf: url(bookID: bookID, photo: false, in: folder)))
    }

    /// Bytes used by all covers and photos.
    static func totalSize(in folder: URL = directory) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    static func thumbnailJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Decoded avatars for the views, keyed by book. `version` changes when an image changes, so
/// views that read it redraw.
@MainActor
@Observable
final class CoverCache {
    static let shared = CoverCache()

    private(set) var version = 0
    @ObservationIgnored private var images: [UUID: UIImage] = [:]
    @ObservationIgnored private var missing: Set<UUID> = []
    /// Books whose avatar shows the initial by choice.
    @ObservationIgnored private var hidden: Set<UUID> = []
    @ObservationIgnored var folder = CoverStore.directory

    /// The reader's photo or the cover, nil when there is neither or the reader chose the initial.
    func image(for bookID: UUID) -> UIImage? {
        _ = version
        if hidden.contains(bookID) { return nil }
        if let image = images[bookID] { return image }
        if missing.contains(bookID) { return nil }
        guard let data = CoverStore.imageData(bookID: bookID, in: folder), let image = UIImage(data: data) else {
            missing.insert(bookID)
            return nil
        }
        images[bookID] = image
        return image
    }

    /// The file the avatar shows (photo, else cover), or nil when it shows the first letter.
    func thumbnailURL(for bookID: UUID) -> URL? {
        if hidden.contains(bookID) { return nil }
        let photo = CoverStore.url(bookID: bookID, photo: true, in: folder)
        if FileManager.default.fileExists(atPath: photo.path) { return photo }
        let cover = CoverStore.url(bookID: bookID, photo: false, in: folder)
        return FileManager.default.fileExists(atPath: cover.path) ? cover : nil
    }

    /// Forgets a book's images after they changed on disk.
    func invalidate(_ bookID: UUID) {
        images[bookID] = nil
        missing.remove(bookID)
        version += 1
    }

    func setHidden(_ bookIDs: Set<UUID>) {
        guard bookIDs != hidden else { return }
        hidden = bookIDs
        version += 1
    }

    func invalidateAll() {
        images = [:]
        missing = []
        version += 1
    }
}
