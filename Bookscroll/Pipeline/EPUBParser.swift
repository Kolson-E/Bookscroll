import Foundation
import ZIPFoundation

/// Read-only access to the files in an EPUB (ZIP) archive.
final class EPUBArchive {
    private let archive: Archive
    private var entries: [String: Entry] = [:]
    private var lowercasedEntries: [String: Entry] = [:]

    init(url: URL) throws {
        do {
            archive = try Archive(url: url, accessMode: .read, pathEncoding: nil)
        } catch {
            throw BookImportError.unreadable("It is not a valid EPUB (ZIP) archive.")
        }
        for entry in archive where entry.type == .file {
            entries[entry.path] = entry
            lowercasedEntries[entry.path.lowercased()] = entry
        }
        if entries.isEmpty {
            throw BookImportError.unreadable("The EPUB archive is empty.")
        }
    }

    var paths: [String] { Array(entries.keys) }

    func contains(_ path: String) -> Bool { entry(for: path) != nil }

    func data(at path: String) throws -> Data? {
        guard let entry = entry(for: path) else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry, skipCRC32: false) { chunk in
                data.append(chunk)
            }
        } catch {
            throw BookImportError.unreadable("A file inside the EPUB is damaged (\(path)).")
        }
        return data
    }

    func text(at path: String) throws -> String? {
        guard let data = try data(at: path) else { return nil }
        return EPUBArchive.decodeText(data)
    }

    private func entry(for path: String) -> Entry? {
        entries[path] ?? lowercasedEntries[path.lowercased()]
    }

    /// Decodes XML/XHTML bytes. Handles UTF-8 and UTF-16 byte order marks, falls back to Latin-1.
    static func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data, encoding: .utf16LittleEndian).map { $0.replacingOccurrences(of: "\u{FEFF}", with: "") }
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16BigEndian).map { $0.replacingOccurrences(of: "\u{FEFF}", with: "") }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }
}

enum EPUBBookParser {
    /// Algorithms that mark font obfuscation, not DRM.
    private static let fontObfuscationAlgorithms: Set<String> = [
        "http://www.idpf.org/2008/embedding",
        "http://ns.adobe.com/pdf/enc#RC",
    ]
    private static let fontExtensions: Set<String> = ["ttf", "otf", "woff", "woff2", "eot"]

    static func parse(url: URL, fallbackTitle: String, progress: (Double) -> Void) throws -> ParsedBook {
        let archive = try EPUBArchive(url: url)
        try checkForDRM(archive)

        guard let containerXML = try archive.text(at: "META-INF/container.xml") else {
            throw BookImportError.unreadable("META-INF/container.xml is missing.")
        }
        guard let opfPath = OPFParser.rootfilePath(containerXML: containerXML),
              let opf = try archive.text(at: opfPath) else {
            throw BookImportError.unreadable("The package document (OPF) is missing.")
        }
        let package = OPFParser.parse(opf: opf, opfPath: opfPath)
        guard !package.spinePaths.isEmpty else {
            throw BookImportError.unreadable("The EPUB has no reading order (spine).")
        }

        var navigationLabels: [String: String] = [:]
        if let navPath = package.navPath, let nav = try archive.text(at: navPath) {
            navigationLabels = EPUBNavigationParser.labels(navDocument: nav, navPath: navPath)
        }
        if navigationLabels.isEmpty, let ncxPath = package.ncxPath, let ncx = try archive.text(at: ncxPath) {
            navigationLabels = EPUBNavigationParser.labels(ncx: ncx, ncxPath: ncxPath)
        }

        var paragraphs: [ParsedParagraph] = []
        var imageRefs: [ImageReference] = []
        /// Images before the first paragraph: they follow the first paragraph.
        var leadingImages: [Int] = []
        var label = ""
        let count = package.spinePaths.count
        for (position, path) in package.spinePaths.enumerated() {
            progress(Double(position) / Double(count) * 0.9)
            try autoreleasepool {
                guard let html = try archive.text(at: path) else { return }
                let blocks = HTMLTextExtractor.blocks(from: html, images: true)
                let document = itemsForDocument(
                    blocks: blocks,
                    navigationLabel: navigationLabels[path],
                    carriedLabel: &label
                )
                // A short cover page's image is the cover, not an illustration.
                let isCoverPage = document.isShort && package.coverPagePaths.contains(path)
                let directory = EPUBPath.directory(of: path)
                for item in document.items {
                    switch item {
                    case var .paragraph(paragraph):
                        paragraph.images = leadingImages
                        leadingImages = []
                        paragraphs.append(paragraph)
                    case let .image(image):
                        let imagePath = EPUBPath.resolve(image.source, relativeTo: directory)
                        guard !isCoverPage, imagePath != package.coverPath else { continue }
                        imageRefs.append(ImageReference(path: imagePath, alt: image.alt))
                        if paragraphs.isEmpty {
                            leadingImages.append(imageRefs.count - 1)
                        } else {
                            paragraphs[paragraphs.count - 1].images.append(imageRefs.count - 1)
                        }
                    }
                }
            }
        }
        let images = loadImages(imageRefs, from: archive, paragraphs: &paragraphs)
        progress(1)

        let title = package.title.map(TextUtils.singleLine).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        let author = package.authors.isEmpty ? "Unknown author" : package.authors.joined(separator: ", ")
        let cover = (try? package.coverPath.flatMap { try archive.data(at: $0) }) ?? coverFromPages(package, archive: archive)
        return ParsedBook(
            title: title,
            author: author,
            format: .epub,
            paragraphs: paragraphs,
            passagesOnly: false,
            note: nil,
            cover: cover,
            images: images
        )
    }

    /// An image the text points to, before it is read from the archive.
    struct ImageReference: Equatable {
        var path: String
        var alt: String
    }

    /// The same image this many times or more is decoration (an ornament at each chapter).
    static let decorationRepeats = 3

    /// Reads the images into a temporary folder and renumbers the paragraphs' image lists.
    /// Missing, unreadable, tiny and repeated images are left out.
    static func loadImages(_ refs: [ImageReference], from archive: EPUBArchive, paragraphs: inout [ParsedParagraph]) -> [ParsedImage] {
        guard !refs.isEmpty else { return [] }
        var uses: [String: Int] = [:]
        for ref in refs { uses[ref.path, default: 0] += 1 }
        let folder = BookImageStore.makeStagingFolder()
        var images: [ParsedImage] = []
        var newIndex: [Int: Int] = [:]
        var prepared: [String: ParsedImage?] = [:]
        for (index, ref) in refs.enumerated() where uses[ref.path, default: 0] < decorationRepeats {
            let image: ParsedImage? = autoreleasepool {
                if let done = prepared[ref.path] { return done.map { ParsedImage(file: $0.file, width: $0.width, height: $0.height, alt: ref.alt) } }
                let result = (try? archive.data(at: ref.path))
                    .flatMap { BookImageStore.prepare($0, name: "\(images.count)", in: folder) }
                    .map { ParsedImage(file: $0.file, width: $0.width, height: $0.height, alt: ref.alt) }
                prepared[ref.path] = .some(result)
                return result
            }
            guard let image else { continue }
            newIndex[index] = images.count
            images.append(image)
        }
        for n in paragraphs.indices where !paragraphs[n].images.isEmpty {
            paragraphs[n].images = paragraphs[n].images.compactMap { newIndex[$0] }
        }
        return images
    }

    /// The image on the book's cover page, for books that do not declare a cover image.
    static func coverFromPages(_ package: EPUBPackage, archive: EPUBArchive) -> Data? {
        for page in package.coverPagePaths {
            guard let html = try? archive.text(at: page),
                  let path = OPFParser.coverImagePath(page: html, pagePath: page),
                  let data = try? archive.data(at: path),
                  CoverStore.thumbnailJPEG(from: data) != nil else { continue }
            return data
        }
        return nil
    }

    /// A paragraph or an image of one spine document, in reading order.
    enum DocumentItem: Equatable {
        case paragraph(ParsedParagraph)
        case image(HTMLImage)
    }

    /// Turns the blocks of one spine document into paragraphs with chapter labels.
    /// Documents under 40 words (cover, table of contents) give no paragraphs.
    static func paragraphsForDocument(
        blocks: [HTMLBlock],
        navigationLabel: String?,
        carriedLabel: inout String
    ) -> [ParsedParagraph] {
        itemsForDocument(blocks: blocks, navigationLabel: navigationLabel, carriedLabel: &carriedLabel).items.compactMap {
            if case let .paragraph(paragraph) = $0 { return paragraph }
            return nil
        }
    }

    /// The paragraphs and images of one spine document. A document under 40 words (cover,
    /// table of contents, a page with only a picture) gives its images only (`isShort`).
    static func itemsForDocument(
        blocks: [HTMLBlock],
        navigationLabel: String?,
        carriedLabel: inout String
    ) -> (items: [DocumentItem], isShort: Bool) {
        let words = blocks.reduce(0) { $0 + TextUtils.wordCount($1.text) }
        guard words >= 40 else {
            return (blocks.compactMap { $0.image.map(DocumentItem.image) }, true)
        }

        if let heading = blocks.first(where: { ($0.headingLevel ?? 99) <= 3 && TextUtils.hasLetterOrDigit($0.text) }) {
            carriedLabel = cleanLabel(heading.text)
        } else if let navigationLabel, !navigationLabel.isEmpty {
            carriedLabel = navigationLabel
        }

        var result: [DocumentItem] = []
        var headingRun: [String] = []
        for block in blocks {
            if let image = block.image {
                result.append(.image(image))
            } else if block.isHeading {
                let text = cleanLabel(block.text)
                guard TextUtils.hasLetterOrDigit(text) else { continue }
                headingRun.append(text)
                carriedLabel = headingRun.joined(separator: ": ")
            } else {
                headingRun.removeAll()
                guard TextUtils.hasLetterOrDigit(block.text) else { continue }
                result.append(.paragraph(ParsedParagraph(text: block.text, chapter: carriedLabel)))
            }
        }
        return (result, false)
    }

    static func cleanLabel(_ text: String) -> String {
        let line = TextUtils.singleLine(text)
        guard line.count > 120 else { return line }
        return String(line.prefix(119)) + "\u{2026}"
    }

    /// Rejects Apple FairPlay, Adobe and other encrypted EPUBs. Font obfuscation is allowed.
    static func checkForDRM(_ archive: EPUBArchive) throws {
        let lowercasedPaths = Set(archive.paths.map { $0.lowercased() })
        if lowercasedPaths.contains("meta-inf/sinf.xml") || lowercasedPaths.contains("meta-inf/rights.xml") {
            throw BookImportError.drmProtected
        }
        guard let encryption = try archive.text(at: "META-INF/encryption.xml") else { return }
        var algorithm = ""
        for token in HTMLTokenizer.tokenize(encryption) {
            guard case let .start(rawName, attributes, _) = token else { continue }
            let name = OPFParser.localName(rawName)
            if name == "encryptionmethod" {
                algorithm = attributes["algorithm"] ?? ""
            } else if name == "cipherreference" {
                let uri = attributes["uri"] ?? ""
                let ext = (uri as NSString).pathExtension.lowercased()
                if !fontObfuscationAlgorithms.contains(algorithm) || !fontExtensions.contains(ext) {
                    throw BookImportError.drmProtected
                }
            }
        }
    }
}
