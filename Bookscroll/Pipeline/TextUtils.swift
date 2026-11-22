import Foundation

enum TextUtils {
    /// Counts runs of non-whitespace characters. Used for every word count in the app and tests.
    static func wordCount<S: StringProtocol>(_ text: S) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                inWord = false
            } else if !inWord {
                inWord = true
                count += 1
            }
        }
        return count
    }

    /// True when the text holds at least one letter or digit. Scene breaks such as `* * *` fail.
    static func hasLetterOrDigit<S: StringProtocol>(_ text: S) -> Bool {
        text.unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
    }

    /// Collapses all whitespace, including line breaks, to single spaces and trims the ends.
    static func singleLine(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = true
            } else {
                if pendingSpace && !output.isEmpty { output.append(" ") }
                pendingSpace = false
                output.append(scalar)
            }
        }
        return String(output)
    }

    /// Substring by UTF-16 offsets. Offsets are clamped to the text.
    static func substring(_ text: NSString, from start: Int, to end: Int) -> String {
        let lower = max(0, min(start, text.length))
        let upper = max(lower, min(end, text.length))
        return text.substring(with: NSRange(location: lower, length: upper - lower))
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Percentage (0...100, rounded down) of `offset` in `total`.
    static func percent(_ offset: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(100, max(0, Int((Double(offset) / Double(total) * 100).rounded(.down))))
    }
}
