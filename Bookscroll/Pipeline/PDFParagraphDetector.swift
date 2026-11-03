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
}

struct DetectedParagraph: Equatable {
    var text: String
    var pageIndex: Int
    /// Top edge (PDF space) of the paragraph's first line.
    var topY: CGFloat
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
            return PDFPageLines(lines: kept, height: page.height)
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

    /// Splits the lines into paragraphs. A new paragraph starts when:
    /// - the vertical gap to the previous line exceeds 1.5 × the page's median line spacing, or
    /// - the line is indented from the page's left margin, or
    /// - the previous line ends in terminal punctuation and is shorter than 80% of the median line width.
    static func detect(_ pages: [PDFPageLines]) -> [DetectedParagraph] {
        let allLines = pages.flatMap { page in page.lines.filter { !$0.text.isEmpty } }
        guard !allLines.isEmpty else { return [] }
        let documentWidth = TextUtils.median(allLines.map { Double($0.rect.width) })
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
        var previous: PDFTextLine?
        var previousMedianWidth = documentWidth

        func finishParagraph() {
            guard !current.isEmpty else { return }
            let text = joinLines(current)
            if TextUtils.hasLetterOrDigit(text) {
                result.append(DetectedParagraph(text: text, pageIndex: currentPage, topY: currentTop))
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

            for (lineIndex, line) in lines.enumerated() {
                var startsParagraph = current.isEmpty
                if !startsParagraph {
                    if line.rect.minX - leftMargin > indentThreshold {
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
            let line = TextUtils.singleLine(raw)
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

    static func endsWithTerminalPunctuation(_ text: String) -> Bool {
        let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]", "\u{00BB}"]
        var trimmed = Substring(text.trimmingCharacters(in: .whitespaces))
        while let last = trimmed.last, closers.contains(last) { trimmed = trimmed.dropLast() }
        guard let last = trimmed.last else { return false }
        return last == "." || last == "!" || last == "?" || last == "\u{2026}"
    }
}
