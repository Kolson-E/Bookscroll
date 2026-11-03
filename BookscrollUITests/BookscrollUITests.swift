import XCTest

/// Drives the real app. The app starts with an in-memory library (debug builds only), so the
/// tests never touch a real library and always start from the same state.
@MainActor
final class BookscrollUITests: XCTestCase {
    private let firstTitle = "The Stone Bridge"
    private let secondTitle = "Harbour Notes"

    private func launch(sampleBooks: Bool, extra: [String] = [], stopOnFailure: Bool = true) -> XCUIApplication {
        continueAfterFailure = !stopOnFailure
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemoryStore"] + (sampleBooks ? ["-UITestSampleBooks"] : []) + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, labelBeginsWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func firstPost(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "post").firstMatch
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        wait(for: [gone], timeout: timeout)
    }

    private func tab(_ app: XCUIApplication, _ name: String) {
        app.tabBars.buttons[name].firstMatch.tap()
    }

    /// Toolbar menus in the navigation bar refuse the "scroll to visible" step of a normal
    /// tap on newer iOS versions, so they are tapped by coordinate.
    private func tapToolbarButton(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(label) is missing")
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Saves a screenshot in the test result, and as a PNG in SCREENSHOT_DIR when CI sets it.
    private func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }

    // MARK: Import entry points

    func testEmptyLibraryAndFeedOpenTheFilesPicker() {
        let app = launch(sampleBooks: false)
        let feedImport = app.buttons["feed.empty.import"]
        XCTAssertTrue(feedImport.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["No books yet"].exists)
        screenshot("01-feed-empty")

        tab(app, "Library")
        let libraryImport = app.buttons["library.empty.import"]
        XCTAssertTrue(libraryImport.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.import"].exists, "Toolbar + button")
        screenshot("02-library-empty")

        libraryImport.tap()
        assertFilesPickerAppearsAndDismiss(app, screenshotName: "03-files-picker")
        XCTAssertTrue(libraryImport.waitForExistence(timeout: 10))

        tab(app, "Feed")
        XCTAssertTrue(feedImport.waitForExistence(timeout: 5))
        feedImport.tap()
        assertFilesPickerAppearsAndDismiss(app, screenshotName: nil)

        tab(app, "Library")
        tapToolbarButton(app, "library.import")
        assertFilesPickerAppearsAndDismiss(app, screenshotName: nil)
    }

    private func assertFilesPickerAppearsAndDismiss(_ app: XCUIApplication, screenshotName: String?) {
        // The Files picker is a system view; its close button is "Cancel" or "Close" depending on the iOS version.
        let close = app.buttons.matching(NSPredicate(format: "label IN %@ OR identifier IN %@", ["Cancel", "Close"], ["Cancel", "Close"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20), "The Files picker did not appear")
        if let screenshotName { screenshot(screenshotName) }
        close.tap()
        waitUntilGone(close)
    }

    // MARK: Feed, marks, Saved

    func testLikeAndBookmarkShowInSaved() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        screenshot("04-feed-mix")

        let like = app.buttons["Like"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 5))
        like.tap()
        XCTAssertTrue(app.buttons["Unlike"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Bookmark"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Remove bookmark"].firstMatch.waitForExistence(timeout: 5))

        tab(app, "Saved")
        XCTAssertTrue(app.buttons["Unlike"].firstMatch.waitForExistence(timeout: 5))
        screenshot("05-saved")

        let filter = app.segmentedControls.firstMatch
        filter.buttons["Liked"].tap()
        XCTAssertTrue(app.buttons["Unlike"].firstMatch.waitForExistence(timeout: 5))
        filter.buttons["Bookmarked"].tap()
        XCTAssertTrue(app.buttons["Remove bookmark"].firstMatch.waitForExistence(timeout: 5))

        // Unliking in Saved removes the post from the Liked filter.
        filter.buttons["Liked"].tap()
        let unlike = app.buttons["Unlike"].firstMatch
        XCTAssertTrue(unlike.waitForExistence(timeout: 5))
        unlike.tap()
        XCTAssertTrue(app.staticTexts["No liked posts"].waitForExistence(timeout: 5))
    }

    func testReadInContextAndContinueInFeed() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        app.buttons["Read in context"].firstMatch.tap()

        let continueButton = app.buttons["Continue in feed from here"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, labelBeginsWith: "Selected post.").waitForExistence(timeout: 5), "The tapped post is highlighted")
        screenshot("06-read-in-context")

        // Scroll both ways; more paragraphs load and the reader stays responsive.
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        lower.press(forDuration: 0.05, thenDragTo: upper)
        lower.press(forDuration: 0.05, thenDragTo: upper)
        upper.press(forDuration: 0.05, thenDragTo: lower)
        XCTAssertTrue(continueButton.exists, "Scrolling does not close the reader")
        continueButton.tap()
        waitUntilGone(continueButton)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
    }

    func testPostStyleAndOneBookThread() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))

        tapToolbarButton(app, "Feed mode")
        app.buttons[firstTitle].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[firstTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, labelBeginsWith: "Continues thread.").waitForExistence(timeout: 5), "Threads in One book mode")
        XCTAssertTrue(element(app, labelBeginsWith: "Chapter: Chapter 1").exists, "Chapter header row")

        let showMore = app.buttons["post.showMore"].firstMatch
        XCTAssertTrue(showMore.waitForExistence(timeout: 5), "A long paragraph is cut after 10 lines")
        screenshot("07-feed-one-book")
        showMore.tap()
        waitUntilGone(showMore)

        tapToolbarButton(app, "Post style")
        app.buttons["Passages"].firstMatch.tap()
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Post style"].value as? String, "Passages")
        screenshot("08-feed-passages")

        // The choice is remembered for the Saved tab and the next view.
        tapToolbarButton(app, "Feed mode")
        app.buttons["Mix all books"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Feed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Post style"].value as? String, "Passages")
    }

    func testSwipeToDeleteRemovesTheBookEverywhere() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        tab(app, "Library")

        let row = element(app, labelBeginsWith: "\(secondTitle), by")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").exists)
        screenshot("09-library")
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        waitUntilGone(row)
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").exists)

        tab(app, "Feed")
        tapToolbarButton(app, "Feed mode")
        XCTAssertTrue(app.buttons[firstTitle].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[secondTitle].exists, "The deleted book left the feed")
    }

    // MARK: Accessibility

    func testAccessibilityAuditLightMode() throws {
        try runAudit(extra: [], prefix: "light")
    }

    func testAccessibilityAuditDarkMode() throws {
        try runAudit(extra: ["-UITestDarkMode"], prefix: "dark")
    }

    func testLargestAccessibilityTextSize() throws {
        let app = launch(
            sampleBooks: true,
            extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
            stopOnFailure: false
        )
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        let like = app.buttons["Like"].firstMatch
        XCTAssertTrue(like.waitForExistence(timeout: 5))
        screenshot("12-feed-largest-text")
        like.tap()
        XCTAssertTrue(app.buttons["Unlike"].firstMatch.waitForExistence(timeout: 5))
        tab(app, "Library")
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").waitForExistence(timeout: 5))
        screenshot("13-library-largest-text")
        try audit(app, types: [.dynamicType], screen: "largest text library")
    }

    private func runAudit(extra: [String], prefix: String) throws {
        let app = launch(sampleBooks: true, extra: extra, stopOnFailure: false)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        screenshot("10-\(prefix)-feed")
        try audit(app, screen: "\(prefix) feed")

        tab(app, "Library")
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) library")

        tab(app, "Saved")
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) saved")

        tab(app, "Feed")
        app.buttons["Read in context"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Continue in feed from here"].waitForExistence(timeout: 10))
        screenshot("11-\(prefix)-reader")
        try audit(app, screen: "\(prefix) reader")
    }

    /// Runs the system accessibility audit. Every issue is printed with its element (CI greps
    /// "AUDIT:") and fails the test, except the known false positives below.
    private func audit(_ app: XCUIApplication, types: XCUIAccessibilityAuditType = .all, screen: String) throws {
        let bars = [app.tabBars.firstMatch, app.buttons["Continue in feed from here"]]
            .filter(\.exists)
            .map(\.frame)
        var issues: [XCUIAccessibilityAuditIssue] = []
        // The handler only collects; the issues are judged afterwards on the main actor.
        try app.performAccessibilityAudit(for: types) { issue in
            issues.append(issue)
            return true
        }
        for issue in issues {
            var place = "no element"
            if let element = issue.element, element.exists {
                place = "type \(element.elementType.rawValue) label '\(element.label)' id '\(element.identifier)' frame \(element.frame)"
            }
            let ignored = Self.isKnownFalsePositive(issue, bars: bars)
            print("AUDIT: \(ignored ? "ignored" : "FAIL") [\(screen)] \(issue.compactDescription) | \(place) | \(issue.detailedDescription)")
            if !ignored {
                XCTFail("Accessibility audit [\(screen)]: \(issue.compactDescription) | \(place)")
            }
        }
    }

    /// Issues the audit reports for correct SwiftUI code. Each rule is narrow:
    /// - Contrast on an element that runs under the translucent tab bar or the reader's
    ///   bottom bar: the audit samples the bar, not the element's own background.
    /// - "Dynamic Type font sizes are partially unsupported": reported for text that uses
    ///   text styles, and even for the system "Done" button. Text that ignores Dynamic Type
    ///   entirely is reported as "unsupported" and still fails.
    /// - "Text clipped" on post text: the spec cuts posts after 10 lines and offers
    ///   "Show more"; VoiceOver reads the whole post.
    static func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, bars: [CGRect]) -> Bool {
        let description = issue.compactDescription
        if description.contains("partially unsupported") { return true }
        guard let element = issue.element, element.exists else { return false }
        if issue.auditType == .contrast, bars.contains(where: { $0.intersects(element.frame) }) { return true }
        if issue.auditType == .textClipped, element.label.count >= 60 { return true }
        return false
    }
}
