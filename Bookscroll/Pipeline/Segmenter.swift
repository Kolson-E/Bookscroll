import Foundation
import NaturalLanguage

/// The normalized text of a book and its segments in both post styles.
struct SegmentedBook: Sendable {
    /// Paragraphs joined by a blank line. Every offset in the app refers to this text,
    /// counted in UTF-16 code units.
    var normalizedText: String
    var totalCharacters: Int
    var paragraphs: [SegmentDraft]
    var passages: [SegmentDraft]
}

/// Builds the normalized text and cuts it into paragraph and passage segments.
/// Segments of one style tile the text: they are contiguous, in order, and cover it exactly.
/// A segment's range includes the blank-line separator that follows it; its `text` does not.
enum Segmenter {
    static let separator = "\n\n"
    static let separatorLength = 2

    static func segment(_ input: [ParsedParagraph]) -> SegmentedBook {
        let paragraphs = clean(input)
        guard !paragraphs.isEmpty else {
            return SegmentedBook(normalizedText: "", totalCharacters: 0, paragraphs: [], passages: [])
        }

        var starts: [Int] = []
        starts.reserveCapacity(paragraphs.count)
        var offset = 0
        for (i, paragraph) in paragraphs.enumerated() {
            starts.append(offset)
            offset += paragraph.text.utf16.count
            if i < paragraphs.count - 1 { offset += separatorLength }
        }
        let total = offset
        let normalized = paragraphs.map(\.text).joined(separator: separator)

        var paragraphSegments: [SegmentDraft] = []
        paragraphSegments.reserveCapacity(paragraphs.count)
        for (i, paragraph) in paragraphs.enumerated() {
            paragraphSegments.append(SegmentDraft(
                style: .paragraph,
                index: i,
                charStart: starts[i],
                charEnd: i + 1 < paragraphs.count ? starts[i + 1] : total,
                chapter: paragraph.chapter,
                text: paragraph.text
            ))
        }

        let passages = passageSegments(paragraphs: paragraphs, starts: starts, total: total, normalized: normalized)
        return SegmentedBook(
            normalizedText: normalized,
            totalCharacters: total,
            paragraphs: paragraphSegments,
            passages: passages
        )
    }

    /// Normalizes paragraph text: trims every line, removes empty lines, and drops paragraphs
    /// without letters or digits. After this step a paragraph never contains a blank line,
    /// so the blank-line separator is unambiguous.
    static func clean(_ paragraphs: [ParsedParagraph]) -> [ParsedParagraph] {
        paragraphs.compactMap { paragraph in
            let text = normalizeParagraphText(paragraph.text)
            guard TextUtils.hasLetterOrDigit(text) else { return nil }
            return ParsedParagraph(text: text, chapter: paragraph.chapter)
        }
    }

    static func normalizeParagraphText(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private struct SentenceUnit {
        var start: Int
        var end: Int
        var words: Int
        var paragraph: Int
        var endsParagraph: Bool
    }

    private static func passageSegments(
        paragraphs: [ParsedParagraph],
        starts: [Int],
        total: Int,
        normalized: String
    ) -> [SegmentDraft] {
        let splitter = SentenceSplitter()
        var units: [SentenceUnit] = []
        for (i, paragraph) in paragraphs.enumerated() {
            let text = paragraph.text as NSString
            let localStarts = splitter.sentenceStarts(in: paragraph.text)
            let paragraphEnd = i + 1 < paragraphs.count ? starts[i + 1] : total
            for (k, localStart) in localStarts.enumerated() {
                let localEnd = k + 1 < localStarts.count ? localStarts[k + 1] : text.length
                let isLast = k == localStarts.count - 1
                units.append(SentenceUnit(
                    start: starts[i] + localStart,
                    end: isLast ? paragraphEnd : starts[i] + localEnd,
                    words: TextUtils.wordCount(TextUtils.substring(text, from: localStart, to: localEnd)),
                    paragraph: i,
                    endsParagraph: isLast
                ))
            }
        }

        let groups = PassageChunker.chunk(units.map {
            PassageChunker.Unit(words: $0.words, endsParagraph: $0.endsParagraph, chapter: paragraphs[$0.paragraph].chapter)
        })

        let full = normalized as NSString
        return groups.enumerated().map { index, range in
            let first = units[range.lowerBound]
            let last = units[range.upperBound - 1]
            let text = TextUtils.substring(full, from: first.start, to: last.end)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return SegmentDraft(
                style: .passage,
                index: index,
                charStart: first.start,
                charEnd: last.end,
                chapter: paragraphs[first.paragraph].chapter,
                text: text
            )
        }
    }
}

/// Groups sentences into passages.
///
/// - A passage closes at about 80 words: before a sentence that would move it further from 80
///   (once it holds at least 40 words).
/// - A passage never exceeds 130 words, unless a single sentence does.
/// - A passage closes at a paragraph end once it holds 40 or more words.
/// - A passage never spans a chapter change.
enum PassageChunker {
    struct Unit: Equatable {
        var words: Int
        var endsParagraph: Bool
        var chapter: String

        init(words: Int, endsParagraph: Bool, chapter: String = "") {
            self.words = words
            self.endsParagraph = endsParagraph
            self.chapter = chapter
        }
    }

    static let targetWords = 80
    static let maximumWords = 130
    static let minimumWordsAtParagraphEnd = 40

    static func chunk(_ units: [Unit]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        var words = 0
        for (i, unit) in units.enumerated() {
            if i > start {
                let chapterChange = unit.chapter != units[start].chapter
                let wouldExceed = words + unit.words > maximumWords
                let movesAwayFromTarget = words >= minimumWordsAtParagraphEnd
                    && abs(words + unit.words - targetWords) > abs(words - targetWords)
                if chapterChange || wouldExceed || movesAwayFromTarget {
                    result.append(start..<i)
                    start = i
                    words = 0
                }
            }
            words += unit.words
            if unit.endsParagraph && words >= minimumWordsAtParagraphEnd {
                result.append(start..<(i + 1))
                start = i + 1
                words = 0
            }
        }
        if start < units.count {
            result.append(start..<units.count)
        }
        return result
    }
}

/// Sentence boundaries from NLTokenizer, as UTF-16 offsets. The first start is always 0.
final class SentenceSplitter {
    private let tokenizer = NLTokenizer(unit: .sentence)

    func sentenceStarts(in text: String) -> [Int] {
        guard !text.isEmpty else { return [] }
        tokenizer.string = text
        var starts: [Int] = [0]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let offset = range.lowerBound.utf16Offset(in: text)
            if offset > starts[starts.count - 1] {
                starts.append(offset)
            }
            return true
        }
        return starts
    }
}

/// Finds the segment that contains an offset.
enum SegmentLocator {
    /// Index of the last segment whose start is at or before `offset`.
    /// For tiled segments this is the segment whose range contains `offset`.
    static func index(containing offset: Int, starts: [Int]) -> Int? {
        guard !starts.isEmpty else { return nil }
        var low = 0
        var high = starts.count - 1
        if offset <= starts[0] { return 0 }
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    static func index(containing offset: Int, in segments: [SegmentDraft]) -> Int? {
        index(containing: offset, starts: segments.map(\.charStart))
    }
}
