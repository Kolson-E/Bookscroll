import Foundation

/// Path arithmetic for files inside an EPUB archive. Archive paths never start with `/`.
enum EPUBPath {
    /// Directory part of an archive path. `OEBPS/content.opf` gives `OEBPS`; `content.opf` gives ``.
    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// Resolves an href found in a file inside `baseDirectory`.
    /// Removes the fragment and query, decodes percent escapes and applies `.` and `..`.
    static func resolve(_ href: String, relativeTo baseDirectory: String) -> String {
        var reference = href
        if let hash = reference.firstIndex(of: "#") { reference = String(reference[..<hash]) }
        if let query = reference.firstIndex(of: "?") { reference = String(reference[..<query]) }
        reference = reference.removingPercentEncoding ?? reference

        var components: [String]
        if reference.hasPrefix("/") {
            components = []
        } else {
            components = baseDirectory.split(separator: "/").map(String.init)
        }
        for part in reference.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    /// Fragment of an href, if any (`ch1.xhtml#p3` gives `p3`).
    static func fragment(of href: String) -> String? {
        guard let hash = href.firstIndex(of: "#") else { return nil }
        let fragment = href[href.index(after: hash)...]
        return fragment.isEmpty ? nil : String(fragment)
    }
}

struct EPUBManifestItem: Equatable {
    var id: String
    /// Full archive path, already resolved.
    var path: String
    var mediaType: String
    var properties: Set<String>
}

struct EPUBPackage: Equatable {
    var title: String?
    var authors: [String]
    var manifest: [String: EPUBManifestItem]
    /// Archive paths of the linear spine items, in reading order.
    var spinePaths: [String]
    /// EPUB 3 navigation document.
    var navPath: String?
    /// EPUB 2 NCX table of contents.
    var ncxPath: String?
    /// The cover image: the EPUB 3 "cover-image" item, else the EPUB 2 `<meta name="cover">`
    /// item, else an image item named "cover".
    var coverPath: String? = nil
}

enum OPFParser {
    /// Reads `META-INF/container.xml` and returns the path of the first OPF rootfile.
    static func rootfilePath(containerXML: String) -> String? {
        var fallback: String?
        for token in HTMLTokenizer.tokenize(containerXML) {
            guard case let .start(name, attributes, _) = token, localName(name) == "rootfile",
                  let path = attributes["full-path"], !path.isEmpty else { continue }
            let mediaType = attributes["media-type"] ?? ""
            if mediaType == "application/oebps-package+xml" { return EPUBPath.resolve(path, relativeTo: "") }
            if fallback == nil { fallback = EPUBPath.resolve(path, relativeTo: "") }
        }
        return fallback
    }

    static func parse(opf: String, opfPath: String) -> EPUBPackage {
        let baseDirectory = EPUBPath.directory(of: opfPath)
        var title: String?
        var authors: [String] = []
        var manifest: [String: EPUBManifestItem] = [:]
        var spineIDs: [String] = []
        var tocID: String?
        var coverMetaID: String?

        var inMetadata = false
        var collecting: String?
        var collected = ""

        for token in HTMLTokenizer.tokenize(opf) {
            switch token {
            case let .start(rawName, attributes, selfClosing):
                let name = localName(rawName)
                switch name {
                case "metadata":
                    if !selfClosing { inMetadata = true }
                case "title", "creator":
                    if inMetadata && !selfClosing {
                        collecting = name
                        collected = ""
                    }
                case "item":
                    guard let id = attributes["id"], let href = attributes["href"] else { break }
                    let properties = Set((attributes["properties"] ?? "").split(separator: " ").map(String.init))
                    manifest[id] = EPUBManifestItem(
                        id: id,
                        path: EPUBPath.resolve(href, relativeTo: baseDirectory),
                        mediaType: attributes["media-type"] ?? "",
                        properties: properties
                    )
                case "meta":
                    if attributes["name"]?.lowercased() == "cover", let content = attributes["content"], !content.isEmpty {
                        coverMetaID = content
                    }
                case "spine":
                    tocID = attributes["toc"]
                case "itemref":
                    guard let idref = attributes["idref"] else { break }
                    if attributes["linear"]?.lowercased() != "no" {
                        spineIDs.append(idref)
                    }
                default:
                    break
                }
            case let .end(rawName):
                let name = localName(rawName)
                if name == "metadata" { inMetadata = false }
                if let field = collecting, field == name {
                    let value = TextUtils.singleLine(collected)
                    if !value.isEmpty {
                        if field == "title" {
                            if title == nil { title = value }
                        } else {
                            authors.append(value)
                        }
                    }
                    collecting = nil
                }
            case let .text(text):
                if collecting != nil { collected += text }
            }
        }

        let spinePaths = spineIDs.compactMap { manifest[$0]?.path }
        let navPath = manifest.values.first { $0.properties.contains("nav") }?.path
        var ncxPath: String?
        if let tocID, let item = manifest[tocID] {
            ncxPath = item.path
        } else {
            ncxPath = manifest.values.first { $0.mediaType == "application/x-dtbncx+xml" }?.path
        }
        let images = manifest.values.filter { $0.mediaType.lowercased().hasPrefix("image/") }.sorted { $0.path < $1.path }
        let coverPath = images.first { $0.properties.contains("cover-image") }?.path
            ?? coverMetaID.flatMap { id in images.first { $0.id == id } }?.path
            ?? images.first { $0.id.lowercased().contains("cover") || ($0.path as NSString).lastPathComponent.lowercased().contains("cover") }?.path
        return EPUBPackage(
            title: title,
            authors: authors,
            manifest: manifest,
            spinePaths: spinePaths,
            navPath: navPath,
            ncxPath: ncxPath,
            coverPath: coverPath
        )
    }

    static func localName(_ name: String) -> String {
        guard let colon = name.lastIndex(of: ":") else { return name }
        return String(name[name.index(after: colon)...])
    }
}

/// Reads chapter titles from the EPUB 3 navigation document or the EPUB 2 NCX.
/// Returns a map from archive path to the first label that points into that file.
enum EPUBNavigationParser {
    static func labels(navDocument: String, navPath: String) -> [String: String] {
        let base = EPUBPath.directory(of: navPath)
        let tokens = HTMLTokenizer.tokenize(navDocument)
        let hasTocNav = tokens.contains { token in
            if case let .start(name, attributes, _) = token, name == "nav" {
                return isToc(attributes)
            }
            return false
        }

        var result: [String: String] = [:]
        var navDepth = 0
        var inToc = false
        var tocDepth = 0
        var currentHref: String?
        var label = ""

        for token in tokens {
            switch token {
            case let .start(name, attributes, selfClosing):
                if name == "nav" && !selfClosing {
                    navDepth += 1
                    if !inToc && (!hasTocNav || isToc(attributes)) {
                        inToc = true
                        tocDepth = navDepth
                    }
                } else if name == "a" && inToc && !selfClosing {
                    currentHref = attributes["href"]
                    label = ""
                }
            case let .end(name):
                if name == "nav" {
                    if inToc && navDepth == tocDepth { inToc = false }
                    navDepth = max(0, navDepth - 1)
                } else if name == "a", let href = currentHref {
                    let text = TextUtils.singleLine(label)
                    let path = EPUBPath.resolve(href, relativeTo: base)
                    if !text.isEmpty && !path.isEmpty && result[path] == nil {
                        result[path] = text
                    }
                    currentHref = nil
                }
            case let .text(text):
                if currentHref != nil { label += text }
            }
        }
        return result
    }

    static func labels(ncx: String, ncxPath: String) -> [String: String] {
        let base = EPUBPath.directory(of: ncxPath)
        var result: [String: String] = [:]
        var inLabel = false
        var inText = false
        var text = ""
        var lastLabel = ""
        for token in HTMLTokenizer.tokenize(ncx) {
            switch token {
            case let .start(rawName, attributes, _):
                let name = OPFParser.localName(rawName)
                if name == "navlabel" {
                    inLabel = true
                } else if name == "text" && inLabel {
                    inText = true
                    text = ""
                } else if name == "content", let src = attributes["src"] {
                    let path = EPUBPath.resolve(src, relativeTo: base)
                    if !lastLabel.isEmpty && !path.isEmpty && result[path] == nil {
                        result[path] = lastLabel
                    }
                }
            case let .end(rawName):
                let name = OPFParser.localName(rawName)
                if name == "text" && inText {
                    inText = false
                    lastLabel = TextUtils.singleLine(text)
                } else if name == "navlabel" {
                    inLabel = false
                }
            case let .text(value):
                if inText { text += value }
            }
        }
        return result
    }

    private static func isToc(_ attributes: [String: String]) -> Bool {
        let type = attributes["epub:type"] ?? attributes["type"] ?? attributes["role"] ?? ""
        return type.split(separator: " ").contains { $0 == "toc" || $0 == "doc-toc" }
    }
}
