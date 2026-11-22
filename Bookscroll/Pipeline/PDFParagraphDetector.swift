import CoreGraphics
import Foundation

/// One line of text on a PDF page. `rect` is in PDF page space (origin bottom left, y up).
struct PDFTextLine: Equatable {
    var text: String
    var rect: CGRect
}

struct PDFPageLines: Equatable {
    var lines: [PDFTextLine]
    var height: CGFloat
    /// 0 when unknown; column detection then does nothing.
    var width: CGFloat = 0
}

struct DetectedParagraph: Equatable {
    var text: String
    var pageIndex: Int
    /// Top edge (PDF space) of the paragraph's first line.
    var topY: CGFloat
    /// Set in larger type than the body text, and short: a heading.
    var isHeading = false
}

/// Rebuilds paragraphs from PDF line geometry. Pure logic, independent of PDFKit.
enum PDFParagraphDetector {
    /// Fraction of the page height at the top and bottom where running headers and footers live.
    static let marginBand: CGFloat = 0.15

    /// Removes lines that recur at the same position on most pages (headers, footers, page numbers).
    /// Digits are ignored when comparing text, so "Page 3" and "Page 4" match.
    static func removeRunningHeadersAndFooters(_ pages: [PDFPageLines]) -> [PDFPageLines] {
        guard pages.count >= 2 else { return pages }
        var pageCounts: [String: Int] = [:]
        let keysPerPage: [[String?]] = pages.map { page in
            page.lines.map { key(for: $0, pageHeight: page.height) }
        }
        for keys in keysPerPage {
            for key in Set(keys.compactMap { $0 }) {
                pageCounts[key, default: 0] += 1
            }
        }
        let repeated = Set(pageCounts.filter { $0.value >= 2 && $0.value * 2 > pages.count }.keys)
        guard !repeated.isEmpty else { return pages }
        return zip(pages, keysPerPage).map { page, keys in
            var kept: [PDFTextLine] = []
            for (line, key) in zip(page.lines, keys) {
                if let key, repeated.contains(key) { continue }
                kept.append(line)
            }
            return PDFPageLines(lines: kept, height: page.height, width: page.width)
        }
    }

    private static func key(for line: PDFTextLine, pageHeight: CGFloat) -> String? {
        let mid = line.rect.midY
        let band = pageHeight * marginBand
        guard mid >= pageHeight - band || mid <= band else { return nil }
        var normalized = ""
        var lastWasDigit = false
        for character in TextUtils.singleLine(line.text).lowercased() {
            if character.isNumber {
                if !lastWasDigit { normalized.append("#") }
                lastWasDigit = true
            } else {
                normalized.append(character)
                lastWasDigit = false
            }
        }
        guard !normalized.isEmpty else { return nil }
        let bucket = Int((mid / 3).rounded())
        return "\(bucket)|\(normalized)"
    }

    // MARK: Columns

    /// Puts a two-column page in reading order: lines across both columns above them (a
    /// title), the left column top to bottom, the right column, then lines across both columns
    /// below. The right column is moved left onto the left column's margin, so its lines are
    /// not taken as indented. A page is two-column when at least three lines sit in each half
    /// and together they hold 70% of the page's lines.
    static func readingOrder(_ page: PDFPageLines) -> PDFPageLines {
        guard page.width > 0, page.lines.count >= 6 else { return page }
        let middle = page.width / 2
        let left = page.lines.filter { $0.rect.maxX <= middle }
        let right = page.lines.filter { $0.rect.minX >= middle }
        guard left.count >= 3, right.count >= 3,
              Double(left.count + right.count) >= 0.7 * Double(page.lines.count) else { return page }
        let spanning = page.lines.filter { $0.rect.maxX > middle && $0.rect.minX < middle }
        let columnsTop = (left + right).map(\.rect.maxY).max() ?? 0
        let above = spanning.filter { $0.rect.midY > columnsTop }
        let below = spanning.filter { $0.rect.midY <= columnsTop }
        let shift = (right.map(\.rect.minX).min() ?? 0) - (left.map(\.rect.minX).min() ?? 0)
        let movedRight = right.map { line in
            PDFTextLine(text: line.text, rect: line.rect.offsetBy(dx: -shift, dy: 0))
        }
        func topToBottom(_ lines: [PDFTextLine]) -> [PDFTextLine] {
            lines.sorted { a, b in
                if abs(a.rect.midY - b.rect.midY) > 1 { return a.rect.midY > b.rect.midY }
                return a.rect.minX < b.rect.minX
            }
        }
        let ordered = topToBottom(above) + topToBottom(left) + topToBottom(movedRight) + topToBottom(below)
        return PDFPageLines(lines: ordered, height: page.height, width: page.width)
    }

    // MARK: Paragraphs

    /// A line is set larger than the body text when its height is at least this many times
    /// the median line height.
    static let headingSizeRatio: CGFloat = 1.3
    /// A drop cap is a single capital at least this many times the median line height.
    static let dropCapSizeRatio: CGFloat = 1.8

    /// Splits the lines into paragraphs. A new paragraph starts when:
    /// - the vertical gap to the previous line exceeds 1.5 × the page's median line spacing, or
    /// - the line is indented from the page's left margin, or
    /// - the previous line ends in terminal punctuation and is shorter than 80% of the median line width, or
    /// - the type changes between heading size and body size.
    /// A drop cap (one large capital) is joined to the word it starts.
    static func detect(_ pages: [PDFPageLines]) -> [DetectedParagraph] {
        let allLines = pages.flatMap { page in page.lines.filter { !$0.text.isEmpty } }
        guard !allLines.isEmpty else { return [] }
        let documentWidth = TextUtils.median(allLines.map { Double($0.rect.width) })
        let bodyHeight = CGFloat(TextUtils.median(allLines.map { Double($0.rect.height) }))
        func isLarge(_ line: PDFTextLine) -> Bool {
            bodyHeight > 0 && line.rect.height >= headingSizeRatio * bodyHeight && TextUtils.wordCount(line.text) <= 15
        }
        func isDropCap(_ line: PDFTextLine) -> Bool {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            return bodyHeight > 0 && text.count == 1 && text.first?.isUppercase == true
                && line.rect.height >= dropCapSizeRatio * bodyHeight
        }
        var documentPitches: [Double] = []
        for page in pages {
            let lines = page.lines.filter { !$0.text.isEmpty }
            for (a, b) in zip(lines, lines.dropFirst()) {
                let pitch = Double(a.rect.minY - b.rect.minY)
                if pitch > 0.5 { documentPitches.append(pitch) }
            }
        }
        let documentPitch = TextUtils.median(documentPitches)

        var result: [DetectedParagraph] = []
        var current: [String] = []
        var currentPage = 0
        var currentTop: CGFloat = 0
        var currentIsLarge = false
        /// Bottom of a drop cap on this page: the lines beside it are indented by its width.
        var dropCapBottom: CGFloat?
        var previous: PDFTextLine?
        var previousMedianWidth = documentWidth

        func finishParagraph() {
            guard !current.isEmpty else { return }
            let text = joinLines(current)
            if TextUtils.hasLetterOrDigit(text) {
                let isHeading = currentIsLarge && current.count <= 3 && TextUtils.wordCount(text) <= 15
                result.append(DetectedParagraph(text: text, pageIndex: currentPage, topY: currentTop, isHeading: isHeading))
            }
            current = []
        }

        for (pageIndex, page) in pages.enumerated() {
            let lines = page.lines.filter { !$0.text.isEmpty }
            guard !lines.isEmpty else { continue }

            var pitches: [Double] = []
            for (a, b) in zip(lines, lines.dropFirst()) {
                let pitch = Double(a.rect.minY - b.rect.minY)
                if pitch > 0.5 { pitches.append(pitch) }
            }
            let medianPitch = pitches.count >= 2 ? TextUtils.median(pitches) : documentPitch
            let medianWidth = lines.count >= 3
                ? TextUtils.median(lines.map { Double($0.rect.width) })
                : documentWidth
            let bodyLines = lines.filter { Double($0.rect.width) >= 0.5 * medianWidth }
            let leftMargin = (bodyLines.isEmpty ? lines : bodyLines).map(\.rect.minX).min() ?? 0
            let indentThreshold = max(4, CGFloat(medianWidth) * 0.02)
            dropCapBottom = nil

            for (lineIndex, line) in lines.enumerated() {
                // "T" set large, then "he river ran": one word.
                if current.count == 1, let last = previous, isDropCap(last), line.text.first?.isLowercase == true {
                    current[0] += line.text
                    currentIsLarge = false
                    dropCapBottom = last.rect.minY
                    previous = line
                    previousMedianWidth = medianWidth
                    continue
                }
                var startsParagraph = current.isEmpty
                if !startsParagraph, let last = previous, isLarge(last) != isLarge(line) {
                    startsParagraph = true
                }
                if !startsParagraph {
                    let besideDropCap = dropCapBottom.map { line.rect.midY > $0 } ?? false
                    if line.rect.minX - leftMargin > indentThreshold, !besideDropCap {
                        startsParagraph = true
                    } else if let previous {
                        if lineIndex > 0, medianPitch > 0 {
                            let gap = Double(previous.rect.minY - line.rect.minY)
                            if gap > 1.5 * medianPitch { startsParagraph = true }
                        }
                        if endsWithTerminalPunctuation(previous.text),
                           Double(previous.rect.width) < 0.8 * previousMedianWidth {
                            startsParagraph = true
                        }
                    }
                }
                if startsParagraph { finishParagraph() }
                if current.isEmpty {
                    currentPage = pageIndex
                    currentTop = line.rect.maxY
                    currentIsLarge = isLarge(line) && !isDropCap(line)
                }
                current.append(line.text)
                previous = line
                previousMedianWidth = medianWidth
            }
        }
        finishParagraph()
        return result
    }

    /// Joins the lines of one paragraph: rejoins words hyphenated at a line end and
    /// collapses the remaining hard wraps to spaces.
    static func joinLines(_ lines: [String]) -> String {
        var output = ""
        for raw in lines {
            let line = TextUtils.singleLine(normalizeGlyphs(raw))
            guard !line.isEmpty else { continue }
            guard let last = output.last else {
                output = line
                continue
            }
            if last == "\u{00AD}" {
                output.removeLast()
                output += line
            } else if last == "-" || last == "\u{2010}" {
                let beforeHyphen = output.dropLast().last
                if beforeHyphen?.isLetter == true, line.first?.isLowercase == true {
                    output.removeLast()
                    output += line
                } else {
                    output += line
                }
            } else if last == "\u{2014}" {
                output += line
            } else {
                output += " " + line
            }
        }
        return output
    }

    /// Typographic ligatures (\u{FB01} and others) that some PDFs keep in their text, as
    /// plain letters, so search and word counts see "fine", not "\u{FB01}ne".
    static func normalizeGlyphs(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0xFB00...0xFB06).contains($0.value) }) else { return text }
        var output = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFB00: output.append(contentsOf: "ff".unicodeScalars)
            case 0xFB01: output.append(contentsOf: "fi".unicodeScalars)
            case 0xFB02: output.append(contentsOf: "fl".unicodeScalars)
            case 0xFB03: output.append(contentsOf: "ffi".unicodeScalars)
            case 0xFB04: output.append(contentsOf: "ffl".unicodeScalars)
            case 0xFB05, 0xFB06: output.append(contentsOf: "st".unicodeScalars)
            default: output.append(scalar)
            }
        }
        return String(output)
    }

    static func endsWithTerminalPunctuation(_ text: String) -> Bool {
        let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]", "\u{00BB}"]
        var trimmed = Substring(text.trimmingCharacters(in: .whitespaces))
        while let last = trimmed.last, closers.contains(last) { trimmed = trimmed.dropLast() }
        guard let last = trimmed.last else { return false }
        return last == "." || last == "!" || last == "?" || last == "\u{2026}"
    }
}
