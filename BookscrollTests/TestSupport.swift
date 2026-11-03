import Foundation
import SwiftData
import XCTest
@testable import Bookscroll

/// In-memory segment source for feed engine tests.
final class InMemorySegmentSource: SegmentSource {
    private(set) var segmentsByBook: [UUID: SegmentedBook] = [:]
    private(set) var fetchCount = 0

    func add(bookID: UUID, segmented: SegmentedBook) {
        segmentsByBook[bookID] = segmented
    }

    func drafts(bookID: UUID, style: PostStyle) -> [SegmentDraft] {
        guard let book = segmentsByBook[bookID] else { return [] }
        return style == .paragraph ? book.paragraphs : book.passages
    }

    func segments(book: FeedBook, style: PostStyle, from index: Int, limit: Int) -> [SegmentRecord] {
        fetchCount += 1
        let all = drafts(bookID: book.id, style: style)
        guard index < all.count, index >= 0 else { return [] }
        return all[index..<min(all.count, index + limit)].map { SegmentRecord(bookID: book.id, draft: $0) }
    }

    func indexContaining(offset: Int, book: FeedBook, style: PostStyle) -> Int? {
        SegmentLocator.index(containing: offset, in: drafts(bookID: book.id, style: style))
    }
}

enum Fixtures {
    static let sentences = [
        "The river ran fast under the old stone bridge.",
        "Nobody in the town could remember when it was built, or by whom.",
        "Children threw sticks from one side and raced across to watch them appear on the other.",
        "Their parents warned them about the current, but the warnings never stuck.",
        "In spring the water rose and the arches sang with a low and steady voice.",
        "By autumn it was quiet again, and the swallows left for warmer places.",
        "\u{201C}Do you hear it?\u{201D} she asked.",
        "He did not answer at first.",
        "Then he nodded, slowly, as if the sound had reached him from very far away.",
        "It was the kind of evening that made people stay out longer than they meant to.",
    ]

    /// Deterministic paragraphs: lengths from one sentence to nine, some dialogue,
    /// chapters every `chapterEvery` paragraphs.
    static func paragraphs(count: Int, chapterEvery: Int = 10, seed: Int = 1) -> [ParsedParagraph] {
        var result: [ParsedParagraph] = []
        var state = seed
        for i in 0..<count {
            state = (state &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
            let sentenceCount = 1 + state % 9
            var text: [String] = []
            for k in 0..<sentenceCount {
                text.append(sentences[(i + k * 3 + state) % sentences.count])
            }
            result.append(ParsedParagraph(text: text.joined(separator: " "), chapter: "Chapter \(i / chapterEvery + 1)"))
        }
        return result
    }

    static func feedBook(id: UUID, ordinal: Int, title: String, segmented: SegmentedBook, position: Int = 0) -> FeedBook {
        FeedBook(
            id: id,
            ordinal: ordinal,
            title: title,
            author: "Author \(ordinal)",
            totalCharacters: segmented.totalCharacters,
            positionOffset: position,
            passagesOnly: false,
            paragraphCount: segmented.paragraphs.count,
            passageCount: segmented.passages.count
        )
    }

    static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Book.self, Segment.self, Mark.self, configurations: configuration)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BookscrollTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Asserts that segments are contiguous, in order, and cover the normalized text exactly.
func assertTiles(_ segments: [SegmentDraft], text: String, file: StaticString = #filePath, line: UInt = #line) {
    let nsText = text as NSString
    guard let first = segments.first, let last = segments.last else {
        XCTAssertEqual(nsText.length, 0, "No segments for non-empty text", file: file, line: line)
        return
    }
    XCTAssertEqual(first.charStart, 0, "First segment does not start at 0", file: file, line: line)
    XCTAssertEqual(last.charEnd, nsText.length, "Last segment does not end at the end of the text", file: file, line: line)
    var rebuilt = ""
    for (i, segment) in segments.enumerated() {
        XCTAssertEqual(segment.index, i, file: file, line: line)
        XCTAssertLessThan(segment.charStart, segment.charEnd, "Empty segment \(i)", file: file, line: line)
        if i > 0 {
            XCTAssertEqual(segments[i - 1].charEnd, segment.charStart, "Gap or overlap before segment \(i)", file: file, line: line)
        }
        let slice = TextUtils.substring(nsText, from: segment.charStart, to: segment.charEnd)
        XCTAssertEqual(segment.text, slice.trimmingCharacters(in: .whitespacesAndNewlines), "Segment \(i) text differs from its range", file: file, line: line)
        rebuilt += slice
    }
    XCTAssertEqual(rebuilt, text, "Segments do not rebuild the text", file: file, line: line)
}

// MARK: - ZIP writer for fixtures

/// Writes an uncompressed (stored) ZIP archive. Independent of the ZIP library the app uses,
/// so the EPUB fixture also checks that the reader handles a third-party archive.
enum ZipWriter {
    static func write(entries: [(path: String, data: Data)], to url: URL) throws {
        var archive = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(archive.count)
            let size = UInt32(entry.data.count)

            archive.appendUInt32(0x0403_4B50)
            archive.appendUInt16(20)          // version needed
            archive.appendUInt16(0x0800)      // UTF-8 names
            archive.appendUInt16(0)           // stored
            archive.appendUInt16(0)           // time
            archive.appendUInt16(0x21)        // date: 1980-01-01
            archive.appendUInt32(crc)
            archive.appendUInt32(size)
            archive.appendUInt32(size)
            archive.appendUInt16(UInt16(name.count))
            archive.appendUInt16(0)
            archive.append(name)
            archive.append(entry.data)

            central.appendUInt32(0x0201_4B50)
            central.appendUInt16(20)          // version made by
            central.appendUInt16(20)          // version needed
            central.appendUInt16(0x0800)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0x21)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(name.count))
            central.appendUInt16(0)           // extra
            central.appendUInt16(0)           // comment
            central.appendUInt16(0)           // disk
            central.appendUInt16(0)           // internal attributes
            central.appendUInt32(0)           // external attributes
            central.appendUInt32(offset)
            central.append(name)
        }
        let centralOffset = UInt32(archive.count)
        archive.append(central)
        archive.appendUInt32(0x0605_4B50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt16(UInt16(entries.count))
        archive.appendUInt32(UInt32(central.count))
        archive.appendUInt32(centralOffset)
        archive.appendUInt16(0)
        try archive.write(to: url)
    }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in data {
            c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        appendUInt16(UInt16(value & 0xFFFF))
        appendUInt16(UInt16(value >> 16))
    }
}
