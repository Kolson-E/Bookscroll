import Foundation
import PDFKit

enum PDFBookParser {
    /// Above this average paragraph length the detection is considered failed.
    static let maximumAverageParagraphWords = 300

    struct OutlineEntry: Equatable {
        var label: String
        var pageIndex: Int
        /// Top of the destination in PDF space. `.greatestFiniteMagnitude` when unspecified.
        var y: CGFloat
    }

    static func parse(url: URL, fallbackTitle: String, progress: (Double) -> Void) throws -> ParsedBook {
        guard let document = PDFDocument(url: url) else {
            throw BookImportError.unreadable("It is not a valid PDF.")
        }
        if document.isLocked && !document.unlock(withPassword: "") {
            throw BookImportError.passwordProtected
        }
        guard document.pageCount > 0 else {
            throw BookImportError.unreadable("The PDF has no pages.")
        }

        var pages: [PDFPageLines] = []
        var letterCount = 0
        for index in 0..<document.pageCount {
            progress(Double(index) / Double(document.pageCount) * 0.9)
            guard let page = document.page(at: index) else {
                pages.append(PDFPageLines(lines: [], height: 0))
                continue
            }
            let lines = extractLines(from: page)
            letterCount += lines.reduce(0) { sum, line in
                sum + line.text.unicodeScalars.filter { $0.properties.isAlphabetic }.count
            }
            pages.append(PDFPageLines(lines: lines, height: page.bounds(for: .mediaBox).height))
        }
        if letterCount < max(20, document.pageCount * 5) {
            throw BookImportError.scannedPDF
        }

        let cleaned = PDFParagraphDetector.removeRunningHeadersAndFooters(pages)
        let detected = PDFParagraphDetector.detect(cleaned)
        guard !detected.isEmpty else { throw BookImportError.noText }

        let outline = outlineEntries(document)
        let paragraphs = assignChapters(detected, outline: outline)
        let passagesOnly = shouldForcePassages(paragraphs)
        progress(1)

        let attributes = document.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String).map(TextUtils.singleLine)
        let author = (attributes[PDFDocumentAttribute.authorAttribute] as? String).map(TextUtils.singleLine)
        return ParsedBook(
            title: (title?.isEmpty == false ? title : nil) ?? fallbackTitle,
            author: (author?.isEmpty == false ? author : nil) ?? "Unknown author",
            format: .pdf,
            paragraphs: paragraphs,
            passagesOnly: passagesOnly,
            note: passagesOnly
                ? "No paragraph breaks were found in this PDF, so it is shown as passages."
                : nil
        )
    }

    static func extractLines(from page: PDFPage) -> [PDFTextLine] {
        let bounds = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: bounds) else { return [] }
        return selection.selectionsByLine().compactMap { line in
            let text = TextUtils.singleLine(line.string ?? "")
            guard !text.isEmpty else { return nil }
            let rect = line.bounds(for: page).offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            return PDFTextLine(text: text, rect: rect)
        }
    }

    static func shouldForcePassages(_ paragraphs: [ParsedParagraph]) -> Bool {
        guard !paragraphs.isEmpty else { return false }
        let words = paragraphs.reduce(0) { $0 + TextUtils.wordCount($1.text) }
        return Double(words) / Double(paragraphs.count) > Double(maximumAverageParagraphWords)
    }

    static func outlineEntries(_ document: PDFDocument) -> [OutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var entries: [OutlineEntry] = []
        func walk(_ node: PDFOutline) {
            for childIndex in 0..<node.numberOfChildren {
                guard let child = node.child(at: childIndex) else { continue }
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                let label = TextUtils.singleLine(child.label ?? "")
                if let destination, let page = destination.page, TextUtils.hasLetterOrDigit(label) {
                    let pageIndex = document.index(for: page)
                    var y = destination.point.y
                    if !y.isFinite || y > 1_000_000 { y = .greatestFiniteMagnitude }
                    entries.append(OutlineEntry(label: label, pageIndex: pageIndex, y: y))
                }
                walk(child)
            }
        }
        walk(root)
        return entries.enumerated().sorted { a, b in
            if a.element.pageIndex != b.element.pageIndex { return a.element.pageIndex < b.element.pageIndex }
            if a.element.y != b.element.y { return a.element.y > b.element.y }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Gives each paragraph the last outline entry that starts at or before it.
    static func assignChapters(_ paragraphs: [DetectedParagraph], outline: [OutlineEntry]) -> [ParsedParagraph] {
        var pointer = 0
        var label = ""
        return paragraphs.map { paragraph in
            while pointer < outline.count {
                let entry = outline[pointer]
                let isBefore = entry.pageIndex < paragraph.pageIndex
                    || (entry.pageIndex == paragraph.pageIndex && entry.y + 1 >= paragraph.topY)
                guard isBefore else { break }
                label = entry.label
                pointer += 1
            }
            return ParsedParagraph(text: paragraph.text, chapter: label)
        }
    }
}
