import Foundation
import PDFKit
import UIKit

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
            // PDFKit returns autoreleased objects; draining per page keeps memory flat on long PDFs.
            let pageLines: PDFPageLines = autoreleasepool {
                guard let page = document.page(at: index) else {
                    return PDFPageLines(lines: [], height: 0)
                }
                let bounds = page.bounds(for: .mediaBox)
                return PDFPageLines(lines: extractLines(from: page), height: bounds.height, width: bounds.width)
            }
            letterCount += pageLines.lines.reduce(0) { sum, line in
                sum + line.text.unicodeScalars.filter { $0.properties.isAlphabetic }.count
            }
            pages.append(pageLines)
        }
        if letterCount < max(20, document.pageCount * 5) {
            throw BookImportError.scannedPDF
        }

        let cleaned = PDFParagraphDetector.removeRunningHeadersAndFooters(pages).map(PDFParagraphDetector.readingOrder)
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
                : nil,
            cover: firstPageImage(document)
        )
    }

    /// The first page as a small JPEG, used as the book's cover.
    static func firstPageImage(_ document: PDFDocument) -> Data? {
        guard let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = 480 / max(bounds.width, bounds.height)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        return image.jpegData(compressionQuality: 0.8)
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
    ///
    /// Headings (short lines in larger type): without an outline, each heading starts a
    /// chapter and is not a post. With an outline, a heading that repeats its chapter's label
    /// is dropped; others stay as posts. When more than a third of the paragraphs look like
    /// headings, type size says nothing in this PDF and is ignored.
    static func assignChapters(_ paragraphs: [DetectedParagraph], outline: [OutlineEntry]) -> [ParsedParagraph] {
        let headingCount = paragraphs.filter(\.isHeading).count
        let usesHeadings = headingCount > 0 && headingCount * 3 <= paragraphs.count
        var pointer = 0
        var label = ""
        var result: [ParsedParagraph] = []
        for paragraph in paragraphs {
            while pointer < outline.count {
                let entry = outline[pointer]
                let isBefore = entry.pageIndex < paragraph.pageIndex
                    || (entry.pageIndex == paragraph.pageIndex && entry.y + 1 >= paragraph.topY)
                guard isBefore else { break }
                label = entry.label
                pointer += 1
            }
            if usesHeadings, paragraph.isHeading {
                if outline.isEmpty {
                    label = paragraph.text
                    continue
                }
                if paragraph.text.compare(label, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                    continue
                }
            }
            result.append(ParsedParagraph(text: paragraph.text, chapter: label))
        }
        return result
    }
}
