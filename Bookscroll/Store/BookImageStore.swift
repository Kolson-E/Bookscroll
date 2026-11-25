import Foundation
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// One image of a book: where it is in the text and how big it is.
struct BookImageEntry: Codable, Equatable, Hashable, Sendable {
    /// End of the text of the paragraph the image follows (see `ImageAnchor`).
    var offset: Int
    /// File name inside the book's image folder.
    var file: String
    var width: Int
    var height: Int
    var alt: String

    /// Height divided by width.
    var aspectRatio: CGFloat {
        width > 0 ? CGFloat(height) / CGFloat(width) : 1
    }

    /// The image belongs to the post (or segment) with this range: the range holds the end
    /// of the text before the image.
    func belongs(toStart start: Int, end: Int) -> Bool {
        start < offset && offset <= end
    }
}

/// The images inside books, as files in Application Support
/// (`BookImages/<book id>/<n>.<ext>`, with `images.json` listing them in text order).
/// Thread-safe: it only reads and writes files.
enum BookImageStore {
    /// Longest side of a stored image, in pixels. Larger images are scaled down at import.
    static let maximumPixelSize = 2048
    /// Larger files are encoded again at import, even when they are small enough in pixels.
    static let maximumKeptBytes = 2_000_000
    /// Smaller images (rules, ornaments, letters drawn as images) are left out.
    static let minimumSide = 40
    static let manifestName = "images.json"

    /// UI tests use a temporary folder (set before anything reads it).
    static var directory = URL.applicationSupportDirectory.appendingPathComponent("BookImages", isDirectory: true)

    static func folder(bookID: UUID, in root: URL = directory) -> URL {
        root.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    /// A new, empty temporary folder for the images of one import.
    static func makeStagingFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BookImages-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Checks image data and writes it as `<name>.<ext>` in `folder`: the original bytes when
    /// they are a common format and not too large, else scaled down (JPEG, or PNG when the
    /// image has transparency). Nil when the data is not an image ImageIO can show, or the
    /// image is too small to be more than decoration.
    static func prepare(_ data: Data, name: String, in folder: URL) -> (file: URL, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = properties[kCGImagePropertyPixelWidth] as? Int,
              var height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        if let orientation = properties[kCGImagePropertyOrientation] as? UInt32, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        guard width >= minimumSide, height >= minimumSide else { return nil }

        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        let keptTypes: [UTType] = [.jpeg, .png, .gif, .heic, .webP]
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        if let type, keptTypes.contains(type), max(width, height) <= maximumPixelSize,
           data.count <= maximumKeptBytes, orientation == 1,
           let ext = type.preferredFilenameExtension {
            let url = folder.appendingPathComponent("\(name).\(ext)")
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
            return (url, width, height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let outputType = hasAlpha ? UTType.png : UTType.jpeg
        let url = folder.appendingPathComponent("\(name).\(hasAlpha ? "png" : "jpg")")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, outputType.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (url, image.width, image.height)
    }

    /// Moves a new book's images into its folder and writes the list. Images without an
    /// anchor are left out. Returns the stored entries, in text order.
    @discardableResult
    static func save(_ images: [ParsedImage], anchors: [ImageAnchor], bookID: UUID, in root: URL = directory) -> [BookImageEntry] {
        guard !anchors.isEmpty else { return [] }
        let folder = folder(bookID: bookID, in: root)
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return [] }
        var entries: [BookImageEntry] = []
        for (n, anchor) in anchors.enumerated() where images.indices.contains(anchor.image) {
            let image = images[anchor.image]
            let name = "\(n).\(image.file.pathExtension)"
            let target = folder.appendingPathComponent(name)
            do {
                if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
                try manager.copyItem(at: image.file, to: target)
            } catch {
                continue
            }
            entries.append(BookImageEntry(offset: anchor.offset, file: name, width: image.width, height: image.height, alt: image.alt))
        }
        entries.sort { $0.offset < $1.offset }
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        }
        return entries
    }

    /// A book's images in text order; empty when it has none.
    static func entries(bookID: UUID, in root: URL = directory) -> [BookImageEntry] {
        let url = folder(bookID: bookID, in: root).appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([BookImageEntry].self, from: data) else { return [] }
        return entries
    }

    static func url(of entry: BookImageEntry, bookID: UUID, in root: URL = directory) -> URL {
        folder(bookID: bookID, in: root).appendingPathComponent(entry.file)
    }

    static func remove(bookID: UUID, in root: URL = directory) {
        try? FileManager.default.removeItem(at: folder(bookID: bookID, in: root))
    }

    /// Bytes used by one book's images.
    static func size(bookID: UUID, in root: URL = directory) -> Int {
        folderSize(folder(bookID: bookID, in: root))
    }

    /// Bytes used by the images of all books.
    static func totalSize(in root: URL = directory) -> Int {
        folderSize(root)
    }

    private static func folderSize(_ folder: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}

/// The book images the views show: each book's list, read once, and decoded images, scaled
/// for the screen and decoded off the main thread.
@MainActor
final class BookImageCache {
    static let shared = BookImageCache()

    /// The folder the images are in. UI tests use a temporary folder.
    var root = BookImageStore.directory {
        didSet { entriesByBook = [:]; decoded.removeAllObjects() }
    }

    private var entriesByBook: [UUID: [BookImageEntry]] = [:]
    private let decoded: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    /// The images that belong to a post or segment with this range, in text order.
    func images(bookID: UUID, start: Int, end: Int) -> [BookImageEntry] {
        let all = entries(bookID: bookID)
        guard !all.isEmpty else { return [] }
        // Entries are sorted by offset: find the first one after `start`.
        var low = 0
        var high = all.count
        while low < high {
            let mid = (low + high) / 2
            if all[mid].offset <= start { low = mid + 1 } else { high = mid }
        }
        var result: [BookImageEntry] = []
        var index = low
        while index < all.count, all[index].offset <= end {
            result.append(all[index])
            index += 1
        }
        return result
    }

    func entries(bookID: UUID) -> [BookImageEntry] {
        if let cached = entriesByBook[bookID] { return cached }
        let entries = BookImageStore.entries(bookID: bookID, in: root)
        entriesByBook[bookID] = entries
        return entries
    }

    func url(of entry: BookImageEntry, bookID: UUID) -> URL {
        BookImageStore.url(of: entry, bookID: bookID, in: root)
    }

    /// Forgets a book's images (after it was deleted or replaced).
    func invalidate(_ bookID: UUID) {
        entriesByBook[bookID] = nil
    }

    /// A decoded image already in memory, at least `pixels` on its longest side.
    func cachedImage(_ entry: BookImageEntry, bookID: UUID, pixels: Int) -> UIImage? {
        decoded.object(forKey: key(entry, bookID: bookID, pixels: pixels))
    }

    /// The image decoded at most `pixels` on its longest side (nil: full size).
    func image(_ entry: BookImageEntry, bookID: UUID, pixels: Int) async -> UIImage? {
        let key = key(entry, bookID: bookID, pixels: pixels)
        if let image = decoded.object(forKey: key) { return image }
        let url = url(of: entry, bookID: bookID)
        let image = await Task.detached(priority: .userInitiated) {
            Self.decode(url, pixels: pixels)
        }.value
        if let image {
            decoded.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        }
        return image
    }

    private func key(_ entry: BookImageEntry, bookID: UUID, pixels: Int) -> NSString {
        "\(bookID.uuidString)/\(entry.file)@\(pixels)" as NSString
    }

    /// Decodes and scales in one step, so the full-size bitmap is never in memory.
    nonisolated private static func decode(_ url: URL, pixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, pixels),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
