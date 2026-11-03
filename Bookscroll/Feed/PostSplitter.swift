import Foundation

/// The "Maximum words per post" setting.
enum WordLimit: Hashable, Sendable {
    /// Each book's own limit: the length that fits 95% of its paragraphs.
    case auto
    case off
    case words(Int)

    static let choices: [WordLimit] = [.auto, .off, .words(60), .words(80), .words(120), .words(200)]

    /// Stored as an integer: -1 auto, 0 off, otherwise the number of words.
    init(storage: Int) {
        switch storage {
        case ..<0: self = .auto
        case 0: self = .off
        default: self = .words(storage)
        }
    }

    var storage: Int {
        switch self {
        case .auto: return -1
        case .off: return 0
        case let .words(count): return count
        }
    }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .off: return "Off"
        case let .words(count): return "\(count) words"
        }
    }

    /// The limit for one book, or nil for no limit.
    func limit(for book: FeedBook) -> Int? {
        switch self {
        case .auto: return book.autoWordLimit > 0 ? book.autoWordLimit : nil
        case .off: return nil
        case let .words(count): return count
        }
    }
}

/// Cuts a long post into parts of at most `limit` words, on sentence boundaries: part one takes
/// as many whole sentences as fit, part two continues from there, and so on. A sentence longer
/// than the limit is cut between words. Parts tile the text, so positions and marks still work.
enum PostSplitter {
    /// UTF-16 ranges, relative to the start of `text`. One range covering the whole text when
    /// the text is within the limit.
    static func parts(of text: String, limit: Int, splitter: SentenceSplitter = SentenceSplitter()) -> [Range<Int>] {
        let length = (text as NSString).length
        guard limit > 0, TextUtils.wordCount(text) > limit else { return [0..<length] }
        let nsText = text as NSString
        let starts = splitter.sentenceStarts(in: text)
        var sentences: [Range<Int>] = []
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : length
            if end > start { sentences.append(start..<end) }
        }

        // Units of at most `limit` words: whole sentences, or word runs of an over-long sentence.
        var units: [(range: Range<Int>, words: Int)] = []
        for sentence in sentences {
            let words = TextUtils.wordCount(nsText.substring(with: NSRange(sentence)))
            if words <= limit {
                units.append((sentence, words))
            } else {
                units.append(contentsOf: wordRuns(nsText, in: sentence, limit: limit))
            }
        }

        // Units are contiguous from 0 to the end of the text, so each cut is at a unit start.
        var parts: [Range<Int>] = []
        var partStart = 0
        var partWords = 0
        for unit in units {
            if partWords > 0 && partWords + unit.words > limit {
                parts.append(partStart..<unit.range.lowerBound)
                partStart = unit.range.lowerBound
                partWords = 0
            }
            partWords += unit.words
        }
        parts.append(partStart..<length)
        return parts
    }

    /// Splits one sentence into runs of `limit` words. Each run ends after the whitespace that
    /// follows its last word.
    private static func wordRuns(_ text: NSString, in range: Range<Int>, limit: Int) -> [(range: Range<Int>, words: Int)] {
        var runs: [(range: Range<Int>, words: Int)] = []
        var runStart = range.lowerBound
        var words = 0
        var inWord = false
        var position = range.lowerBound
        while position < range.upperBound {
            let isSpace = isWhitespace(text.character(at: position))
            if !isSpace && !inWord {
                if words == limit {
                    runs.append((runStart..<position, words))
                    runStart = position
                    words = 0
                }
                words += 1
            }
            inWord = !isSpace
            position += 1
        }
        if range.upperBound > runStart {
            runs.append((runStart..<range.upperBound, words))
        }
        return runs
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return scalar.properties.isWhitespace
    }
}
