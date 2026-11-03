import Foundation

enum HTMLToken: Equatable {
    case start(name: String, attributes: [String: String], selfClosing: Bool)
    case end(name: String)
    case text(String)
}

/// A lenient tokenizer for XHTML, HTML and the XML files inside an EPUB.
/// It never fails: malformed markup degrades to text. Tag and attribute names are lowercased.
/// Text tokens have their character references decoded. The content of `script` and `style`
/// is dropped.
enum HTMLTokenizer {
    private static let lessThan = UInt8(ascii: "<")
    private static let greaterThan = UInt8(ascii: ">")
    private static let slash = UInt8(ascii: "/")
    private static let bang = UInt8(ascii: "!")
    private static let question = UInt8(ascii: "?")
    private static let equals = UInt8(ascii: "=")
    private static let doubleQuote = UInt8(ascii: "\"")
    private static let singleQuote = UInt8(ascii: "'")

    static let rawTextElements: Set<String> = ["script", "style"]

    static func tokenize(_ source: String) -> [HTMLToken] {
        let bytes = Array(source.utf8)
        let n = bytes.count
        var tokens: [HTMLToken] = []
        var i = 0
        var textStart = 0

        func emitText(upTo end: Int) {
            guard end > textStart else { return }
            let raw = String(decoding: bytes[textStart..<end], as: UTF8.self)
            tokens.append(.text(HTMLEntities.decode(raw)))
        }

        while i < n {
            guard bytes[i] == lessThan, i + 1 < n else {
                i += 1
                continue
            }
            let next = bytes[i + 1]
            if next == bang {
                emitText(upTo: i)
                if hasPrefix(bytes, at: i, "<!--") {
                    let close = find(bytes, "-->", from: i + 4) ?? n
                    i = min(n, close + 3)
                } else if hasPrefix(bytes, at: i, "<![CDATA[") {
                    let start = i + 9
                    let close = find(bytes, "]]>", from: start) ?? n
                    if close > start {
                        tokens.append(.text(String(decoding: bytes[start..<close], as: UTF8.self)))
                    }
                    i = min(n, close + 3)
                } else {
                    let close = find(bytes, ">", from: i + 2) ?? n
                    i = min(n, close + 1)
                }
                textStart = i
                continue
            }
            if next == question {
                emitText(upTo: i)
                let close = find(bytes, ">", from: i + 2) ?? n
                i = min(n, close + 1)
                textStart = i
                continue
            }
            if next == slash {
                guard i + 2 < n, isNameStart(bytes[i + 2]) else {
                    i += 1
                    continue
                }
                emitText(upTo: i)
                var j = i + 2
                while j < n, isNameChar(bytes[j]) { j += 1 }
                let name = lowercased(bytes[(i + 2)..<j])
                let close = find(bytes, ">", from: j) ?? n
                tokens.append(.end(name: name))
                i = min(n, close + 1)
                textStart = i
                continue
            }
            if isNameStart(next) {
                emitText(upTo: i)
                let parsed = parseStartTag(bytes, nameStart: i + 1)
                tokens.append(parsed.token)
                i = parsed.next
                textStart = i
                if case let .start(name, _, selfClosing) = parsed.token,
                   !selfClosing, rawTextElements.contains(name) {
                    // Skip raw text. The closing tag is tokenized normally on the next pass.
                    i = findCaseInsensitive(bytes, "</" + name, from: i) ?? n
                    textStart = i
                }
                continue
            }
            i += 1
        }
        emitText(upTo: n)
        return tokens
    }

    // MARK: - Helpers

    private static func parseStartTag(_ bytes: [UInt8], nameStart: Int) -> (token: HTMLToken, next: Int) {
        let n = bytes.count
        var j = nameStart
        while j < n, isNameChar(bytes[j]) { j += 1 }
        let name = lowercased(bytes[nameStart..<j])
        var attributes: [String: String] = [:]
        var selfClosing = false
        while j < n {
            let c = bytes[j]
            if isSpace(c) {
                j += 1
                continue
            }
            if c == greaterThan {
                return (.start(name: name, attributes: attributes, selfClosing: selfClosing), j + 1)
            }
            if c == slash {
                selfClosing = true
                j += 1
                continue
            }
            selfClosing = false
            let attributeStart = j
            while j < n, !isSpace(bytes[j]), bytes[j] != equals, bytes[j] != greaterThan,
                  !(bytes[j] == slash && j + 1 < n && bytes[j + 1] == greaterThan) {
                j += 1
            }
            if j == attributeStart {
                j += 1
                continue
            }
            let attributeName = lowercased(bytes[attributeStart..<j])
            while j < n, isSpace(bytes[j]) { j += 1 }
            var value = ""
            if j < n, bytes[j] == equals {
                j += 1
                while j < n, isSpace(bytes[j]) { j += 1 }
                if j < n, bytes[j] == doubleQuote || bytes[j] == singleQuote {
                    let quote = bytes[j]
                    j += 1
                    let valueStart = j
                    while j < n, bytes[j] != quote { j += 1 }
                    value = String(decoding: bytes[valueStart..<j], as: UTF8.self)
                    if j < n { j += 1 }
                } else {
                    let valueStart = j
                    while j < n, !isSpace(bytes[j]), bytes[j] != greaterThan { j += 1 }
                    value = String(decoding: bytes[valueStart..<j], as: UTF8.self)
                }
            }
            if attributes[attributeName] == nil {
                attributes[attributeName] = HTMLEntities.decode(value)
            }
        }
        return (.start(name: name, attributes: attributes, selfClosing: selfClosing), n)
    }

    private static func isSpace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C
    }

    private static func isNameStart(_ c: UInt8) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    }

    private static func isNameChar(_ c: UInt8) -> Bool {
        isNameStart(c) || (c >= 48 && c <= 57) || c == 45 || c == 95 || c == 58 || c == 46
    }

    private static func lower(_ c: UInt8) -> UInt8 {
        (c >= 65 && c <= 90) ? c + 32 : c
    }

    private static func lowercased(_ slice: ArraySlice<UInt8>) -> String {
        String(decoding: slice.map(lower), as: UTF8.self)
    }

    private static func hasPrefix(_ bytes: [UInt8], at index: Int, _ prefix: String) -> Bool {
        let p = Array(prefix.utf8)
        guard index + p.count <= bytes.count else { return false }
        for k in 0..<p.count where bytes[index + k] != p[k] { return false }
        return true
    }

    private static func find(_ bytes: [UInt8], _ pattern: String, from start: Int) -> Int? {
        let p = Array(pattern.utf8)
        guard !p.isEmpty, start >= 0, bytes.count - p.count >= start else { return nil }
        var i = start
        while i <= bytes.count - p.count {
            if bytes[i] == p[0] {
                var k = 1
                while k < p.count, bytes[i + k] == p[k] { k += 1 }
                if k == p.count { return i }
            }
            i += 1
        }
        return nil
    }

    private static func findCaseInsensitive(_ bytes: [UInt8], _ pattern: String, from start: Int) -> Int? {
        let p = Array(pattern.utf8).map(lower)
        guard !p.isEmpty, start >= 0, bytes.count - p.count >= start else { return nil }
        var i = start
        while i <= bytes.count - p.count {
            var k = 0
            while k < p.count, lower(bytes[i + k]) == p[k] { k += 1 }
            if k == p.count { return i }
            i += 1
        }
        return nil
    }
}
