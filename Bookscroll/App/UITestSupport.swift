#if DEBUG
import Foundation
import SwiftData
import SwiftUI

/// Launch arguments for the UI tests. Compiled into debug builds only.
@MainActor
enum UITestSupport {
    /// Use an empty in-memory library and default settings.
    static let inMemoryArgument = "-UITestInMemoryStore"
    /// Also add two generated sample books.
    static let sampleBooksArgument = "-UITestSampleBooks"
    // Settings can be given as launch arguments, for example `-appTheme light`: UserDefaults
    // reads them before the stored values.

    static func makeContainerIfRequested() -> ModelContainer? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(inMemoryArgument) else { return nil }
        for key in ["postStyle", "feedMode", "singleBookID", "feedShelfID", FeedModeChoice.chosenBooksKey, "savedFilter", "savedBookmarkColor", "shareCardStyle", "shareCardTheme", "librarySort", "libraryStatus", "libraryFormat", FeedViewModel.mixTopBookKey, FocusFeed.key] + AppSettings.Key.all + FolderSync.Key.all + BookFinder.Key.all {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let container: ModelContainer
        do {
            container = try LibraryContainer.make(inMemory: true)
        } catch {
            fatalError("The UI test library could not be created: \(error)")
        }
        if arguments.contains(sampleBooksArgument) {
            do {
                try addSampleBooks(to: container.mainContext)
            } catch {
                fatalError("The UI test sample books could not be added: \(error)")
            }
        }
        return container
    }

    static let sampleTitles = ["The Stone Bridge", "Harbour Notes"]

    private static let sentences = [
        "The river ran fast under the old stone bridge.",
        "Nobody in the town could remember when it was built, or by whom.",
        "Children threw sticks from one side and raced across to watch them appear on the other.",
        "Their parents warned them about the current, but the warnings never stuck.",
        "In spring the water rose and the arches sang with a low and steady voice.",
        "By autumn it was quiet again, and the swallows left for warmer places.",
        "He did not answer at first.",
        "Then he nodded, slowly, as if the sound had reached him from very far away.",
    ]

    private static func addSampleBooks(to context: ModelContext) throws {
        let books: [(title: String, author: String, paragraphs: Int, chapterEvery: Int)] = [
            (sampleTitles[0], "Ada Lane", 60, 12),
            (sampleTitles[1], "Ben Ito", 40, 10),
        ]
        for (n, sample) in books.enumerated() {
            var paragraphs: [ParsedParagraph] = []
            for i in 0..<sample.paragraphs {
                // The second paragraph of the first book is long, so "Show more" appears.
                let count = (n == 0 && i == 1) ? 18 : 1 + (i * 7 + n) % 5
                let text = (0..<count).map { sentences[(i + $0 * 3 + n) % sentences.count] }.joined(separator: " ")
                paragraphs.append(ParsedParagraph(text: text, chapter: "Chapter \(i / sample.chapterEvery + 1)"))
            }
            let parsed = ParsedBook(
                title: sample.title,
                author: sample.author,
                format: .epub,
                paragraphs: paragraphs,
                passagesOnly: false,
                note: nil
            )
            _ = try BookWriter.write(parsed: parsed, segmented: Segmenter.segment(parsed.paragraphs), into: context)
        }
    }
}
#endif
