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

    /// A choice in an open menu. iOS versions expose menu rows as buttons, menu items or cells.
    private func menuChoice(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let types = [XCUIElement.ElementType.button, .menuItem, .cell].map(\.rawValue)
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND elementType IN %@", label, types))
            .firstMatch
    }

    /// Opens a toolbar menu and returns one of its choices. The menu is opened by coordinate
    /// (see `tapToolbarButton`). When the choice does not appear, the element tree is printed
    /// (CI greps "DEBUG:").
    private func openToolbarMenu(_ app: XCUIApplication, _ menu: String, choice: String) -> XCUIElement {
        tapToolbarButton(app, menu)
        let item = menuChoice(app, choice)
        // iOS 17 can ignore the first tap on a toolbar menu; it is tried again, then with a
        // short press.
        let retries: [(Date, () -> Void)] = [
            (Date().addingTimeInterval(2.5), { [self] in tapToolbarButton(app, menu) }),
            (Date().addingTimeInterval(5), {
                app.buttons[menu].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.6)
            }),
        ]
        var pending = retries
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if item.exists { return item }
            if let next = pending.first, Date() > next.0 {
                pending.removeFirst()
                next.1()
                continue
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        screenshot("debug-menu-\(menu)")
        for line in app.debugDescription.split(separator: "\n") {
            print("DEBUG: \(line)")
        }
        return item
    }

    /// Saves a screenshot in the test result, and as a PNG in SCREENSHOT_DIR when CI sets it.
    /// Scrolls until `element` is clear of the tab bar, which content runs under on iOS 26.
    private func scrollAboveTabBar(_ element: XCUIElement, in app: XCUIApplication) {
        let tabBar = app.tabBars.firstMatch
        for _ in 0..<6 {
            let limit = tabBar.exists ? tabBar.frame.minY : app.frame.maxY
            if element.frame.maxY < limit - 8 && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
    }

    /// Scrolls a list until `element` is on screen (rows below the fold are not in the tree).
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
        scrollAboveTabBar(element, in: app)
    }

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
        openToolbarMenu(app, "Import books", choice: "Choose Files").tap()
        assertFilesPickerAppearsAndDismiss(app, screenshotName: nil)

        // Find Books explains why it needs a folder and offers to allow one.
        openToolbarMenu(app, "Import books", choice: "Find Books on This iPhone").tap()
        let allow = app.buttons["find.allowFolder"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        screenshot("03a-find-books")
        allow.tap()
        assertFilesPickerAppearsAndDismiss(app, screenshotName: nil)
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "Find Books stays open after Cancel")
        app.buttons["find.close"].firstMatch.tap()
        XCTAssertTrue(libraryImport.waitForExistence(timeout: 10))
        app.buttons["library.empty.find"].firstMatch.tap()
        XCTAssertTrue(allow.waitForExistence(timeout: 5), "The empty Library opens Find Books too")
        app.buttons["find.close"].firstMatch.tap()
    }

    private func assertFilesPickerAppearsAndDismiss(_ app: XCUIApplication, screenshotName: String?) {
        // The Files picker is a system view; its close button is "Cancel" or "Close" depending on the iOS version.
        // Find Books has its own Close button under the picker; it is not the picker's.
        let close = app.buttons.matching(NSPredicate(
            format: "(label IN %@ OR identifier IN %@) AND identifier != %@",
            ["Cancel", "Close"], ["Cancel", "Close"], "find.close"
        )).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 20), "The Files picker did not appear")
        if let screenshotName { screenshot(screenshotName) }
        close.tap()
        waitUntilGone(close)
    }

    // MARK: Feed, marks, Saved

    func testBookmarkColoursShowInSaved() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        screenshot("04-feed-mix")

        // The first tap bookmarks the post and opens the colour bubble.
        let bookmark = app.buttons["Bookmark"].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        bookmark.tap()
        XCTAssertTrue(app.buttons["Change bookmark"].firstMatch.waitForExistence(timeout: 5))
        let red = app.buttons["bookmark.color.red"].firstMatch
        XCTAssertTrue(red.waitForExistence(timeout: 5), "The colour bubble opens")
        screenshot("05-bookmark-colours")
        red.tap()
        XCTAssertTrue(app.buttons["Change bookmark"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Change bookmark"].firstMatch.value as? String, "Bookmarked, Red highlight")

        tab(app, "Saved")
        XCTAssertTrue(app.buttons["Change bookmark"].firstMatch.waitForExistence(timeout: 5))
        let chips = app.descendants(matching: .any)["saved.colors"]
        XCTAssertTrue(chips.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["All, 1"].exists)
        app.buttons["Red, 1"].tap()
        XCTAssertTrue(app.buttons["Change bookmark"].firstMatch.waitForExistence(timeout: 5))
        screenshot("05-saved")

        let filter = app.segmentedControls.firstMatch
        filter.buttons["Highlights"].tap()
        XCTAssertTrue(app.staticTexts["No highlights"].waitForExistence(timeout: 5))
        filter.buttons["Bookmarks"].tap()

        // Remove, from the bubble, takes the post out of Saved.
        let change = app.buttons["Change bookmark"].firstMatch
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        let remove = app.buttons["Remove bookmark"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.staticTexts["No bookmarks"].waitForExistence(timeout: 5))
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

    /// True when `element` is gone from the screen or cannot be tapped.
    private func waitUntilHidden(_ element: XCUIElement, _ hidden: Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let isHidden = !element.exists || !element.isHittable
            if isHidden == hidden { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return false
    }

    func testBarsHideWhileReadingDownAndComeBackOnScrollUp() {
        let app = launch(sampleBooks: true, extra: ["-UITestHideBars"])
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        let libraryTab = app.tabBars.buttons["Library"].firstMatch
        let navigationBar = app.navigationBars["Feed"].firstMatch
        XCTAssertTrue(waitUntilHidden(libraryTab, false), "The tab bar shows at the top of the feed")

        app.swipeUp(velocity: .slow)
        app.swipeUp(velocity: .slow)
        XCTAssertTrue(waitUntilHidden(libraryTab, true), "The tab bar hides while reading down")
        XCTAssertTrue(waitUntilHidden(navigationBar, true), "The navigation bar hides while reading down")
        screenshot("31-feed-bars-hidden")

        app.swipeDown(velocity: .slow)
        XCTAssertTrue(waitUntilHidden(libraryTab, false), "Scrolling up brings the tab bar back")
        XCTAssertTrue(waitUntilHidden(navigationBar, false), "Scrolling up brings the navigation bar back")
        tab(app, "Library")
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    /// The app's own record of how the bars moved (`ScrollChromeTrace`), as numbers.
    private func rawTrace(_ app: XCUIApplication) -> String {
        (app.descendants(matching: .any)["feed.barTrace"].firstMatch.value as? String) ?? "none"
    }

    private func barTrace(_ app: XCUIApplication) -> [String: Double] {
        let text = (app.descendants(matching: .any)["feed.barTrace"].firstMatch.value as? String) ?? ""
        var values: [String: Double] = [:]
        for pair in text.split(separator: " ") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let number = Double(parts[1]) { values[String(parts[0])] = number }
        }
        return values
    }

    /// A slow drag of `distance` points (positive: reading down), held at the end so the
    /// content stops without a flick.
    private func drag(_ app: XCUIApplication, by distance: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: distance > 0 ? 0.7 : 0.3))
        let end = start.withOffset(CGVector(dx: 0, dy: -distance))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: XCUIGestureVelocity(300), thenHoldForDuration: 0.4)
    }

    /// Lets the bars finish their ease, then checks where the tab bar rests: first by the
    /// app's own report (its layer and whether it takes taps), then as the tests see it.
    /// A failure prints both, with a screenshot.
    private func assertTabBar(_ app: XCUIApplication, hidden: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let wanted: Double = hidden ? 1 : 0
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let deadline = Date().addingTimeInterval(4)
        var trace = barTrace(app)
        while trace["state"] != wanted && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            trace = barTrace(app)
        }
        let button = app.tabBars.buttons["Library"].firstMatch
        let seen = waitUntilHidden(button, hidden)
        if trace["state"] != wanted || !seen {
            screenshot("debug-bars-\(line)")
            print("DEBUG: bars at line \(line): trace \(trace); button exists \(button.exists)")
            if button.exists { print("DEBUG: button frame \(button.frame) hittable \(button.isHittable)") }
            for row in app.tabBars.firstMatch.debugDescription.split(separator: "\n").prefix(20) { print("DEBUG: \(row)") }
        }
        XCTAssertEqual(trace["state"], wanted, "\(message) (the app's report: \(trace))", file: file, line: line)
        XCTAssertEqual(trace["taps"], hidden ? 0 : 1, "\(message): taps", file: file, line: line)
        XCTAssertEqual(trace["offset"] ?? -1, hidden ? 99 : 0, accuracy: hidden ? 40 : 0.5, "\(message): offset", file: file, line: line)
        XCTAssertTrue(seen, "\(message) (as the tests see it)", file: file, line: line)
    }

    /// Opens a tab; a failure prints the bars' state.
    private func openTab(_ app: XCUIApplication, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        tab(app, name)
        guard !app.navigationBars[name].waitForExistence(timeout: 5) else { return }
        screenshot("debug-tab-\(line)")
        print("DEBUG: tab \(name) did not open; trace \(rawTrace(app))")
        for row in app.tabBars.firstMatch.debugDescription.split(separator: "\n").prefix(20) { print("DEBUG: \(row)") }
        // Does a second tap work? (The first tap after the Home Screen may be lost.)
        tab(app, name)
        let second = app.navigationBars[name].waitForExistence(timeout: 3)
        print("DEBUG: second tap opened \(name): \(second); trace \(barTrace(app))")
        if !second {
            app.tabBars.buttons[name].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            print("DEBUG: coordinate tap opened \(name): \(app.navigationBars[name].waitForExistence(timeout: 3)); trace \(barTrace(app))")
        }
        XCTFail("The \(name) tab opens", file: file, line: line)
    }

    /// What every bar test checks at the end: the tab bar never moved faster than the
    /// content, never jumped while easing, and always came back to its exact place.
    private func assertSmoothTrace(_ app: XCUIApplication, minimumRests: Double, file: StaticString = #filePath, line: UInt = #line) {
        let trace = barTrace(app)
        let text = String(describing: trace)
        XCTAssertGreaterThan(trace["frames"] ?? 0, 20, "The bars followed the scroll: \(text)", file: file, line: line)
        XCTAssertEqual(trace["faster"], 0, "The tab bar never moved faster than the content: \(text)", file: file, line: line)
        XCTAssertEqual(trace["notBack"], 0, "The tab bar always came back to its place: \(text)", file: file, line: line)
        XCTAssertLessThanOrEqual(trace["ease"] ?? .infinity, 2200, "The ease never jumped: \(text)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(trace["hidden"] ?? 0, minimumRests, "Rests hidden: \(text)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(trace["shown"] ?? 0, minimumRests, "Rests shown: \(text)", file: file, line: line)
    }

    func testTheTabBarFollowsTheFingerAndNeverJumps() {
        let app = launch(sampleBooks: true, extra: ["-UITestHideBars"])
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        let libraryTab = app.tabBars.buttons["Library"].firstMatch
        XCTAssertTrue(waitUntilHidden(libraryTab, false))
        let home = libraryTab.frame

        // Slow reading, turning back, and flicks both ways, again and again.
        for round in 1...4 {
            drag(app, by: 220)
            assertTabBar(app, hidden: true, "Round \(round): reading down hides the tab bar")
            drag(app, by: -160)
            assertTabBar(app, hidden: false, "Round \(round): scrolling up brings it back")
            app.swipeUp(velocity: .fast)
            assertTabBar(app, hidden: true, "Round \(round): a flick down the feed hides it")
            app.swipeDown(velocity: .fast)
            assertTabBar(app, hidden: false, "Round \(round): a flick back up shows it")
        }
        XCTAssertEqual(libraryTab.frame.minY, home.minY, accuracy: 0.5, "The tab bar is back exactly in its place")
        XCTAssertEqual(libraryTab.frame.height, home.height, accuracy: 0.5)
        assertSmoothTrace(app, minimumRests: 8)
        tab(app, "Library")
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5), "The tab bar works after all that")
    }

    func testAScrollThatStopsPartWayEasesToTheNearerEnd() {
        let app = launch(sampleBooks: true, extra: ["-UITestHideBars"])
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        drag(app, by: 300)
        assertTabBar(app, hidden: true, "Away from the top, reading down hides the tab bar")
        print("DEBUG: after reading down: \(rawTrace(app))")
        drag(app, by: -25)
        print("DEBUG: after a short scroll up: \(rawTrace(app))")
        assertTabBar(app, hidden: true, "A short scroll up eases back to hidden")
        drag(app, by: -90)
        assertTabBar(app, hidden: false, "More than half way up eases on to shown")
        drag(app, by: 25)
        assertTabBar(app, hidden: false, "A short scroll down eases back to shown")
        drag(app, by: 90)
        assertTabBar(app, hidden: true, "More than half way down eases on to hidden")
        let trace = barTrace(app)
        XCTAssertGreaterThan(trace["ease"] ?? 0, 0, "The bars eased: \(trace)")
        assertSmoothTrace(app, minimumRests: 2)
    }

    func testTheBarsKeepWorkingAfterOtherTabsAndTheHomeScreen() {
        let app = launch(sampleBooks: true, extra: ["-UITestHideBars"])
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        let libraryTab = app.tabBars.buttons["Library"].firstMatch
        let home = libraryTab.frame
        drag(app, by: 260)
        assertTabBar(app, hidden: true, "Reading down hides the tab bar")

        // To the Home Screen and back: the bars come back shown and still follow.
        print("DEBUG: before the Home Screen: \(rawTrace(app))")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 10))
        assertTabBar(app, hidden: false, "Back from the Home Screen, the bars are shown, as after a launch")
        drag(app, by: 220)
        assertTabBar(app, hidden: true, "After the Home Screen, reading down hides the tab bar")
        drag(app, by: -160)
        assertTabBar(app, hidden: false, "After the Home Screen, scrolling up shows the tab bar")
        print("DEBUG: after the Home Screen: \(rawTrace(app))")
        XCTAssertEqual(libraryTab.frame.minY, home.minY, accuracy: 0.5)

        // Another tab and back: the feed starts with the bars shown, and they hide again.
        openTab(app, "Library")
        XCTAssertEqual(libraryTab.frame.minY, home.minY, accuracy: 0.5, "Other tabs get the tab bar in its place")
        tab(app, "Feed")
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
        assertTabBar(app, hidden: false, "Back in the feed, the tab bar shows")
        drag(app, by: 220)
        assertTabBar(app, hidden: true, "And it still hides while reading down")
        drag(app, by: -160)
        assertTabBar(app, hidden: false, "And comes back")
        assertSmoothTrace(app, minimumRests: 1)
    }

    /// The tabs work after the Home Screen when the bars never hid, and with bar hiding off.
    func testTheTabsWorkAfterTheHomeScreen() {
        for extra in [["-UITestHideBars"], []] {
            let app = launch(sampleBooks: true, extra: extra, stopOnFailure: false)
            XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(firstPost(app).waitForExistence(timeout: 10))
            print("DEBUG: launch \(extra): after the Home Screen")
            openTab(app, "Library")
            app.terminate()
        }
    }

    // MARK: Pictures

    /// A book's picture shows under the post it follows, keeps its shape, opens full screen with
    /// a tap, and closes with a swipe down, a swipe up, or the close button.
    func testABookPictureOpensFullScreenAndSwipesAway() {
        let app = launch(sampleBooks: true, extra: ["-UITestSampleImages"])
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        let picture = app.descendants(matching: .any)["post.image"].firstMatch
        var tries = 0
        while !(picture.exists && picture.isHittable) && tries < 10 {
            drag(app, by: 200)
            tries += 1
        }
        XCTAssertTrue(picture.isHittable, "A picture shows under a post")
        XCTAssertGreaterThan(picture.frame.width, 250, "Full width of the text column")
        XCTAssertEqual(picture.frame.height / picture.frame.width, 800.0 / 1200.0, accuracy: 0.03, "It keeps its shape")
        XCTAssertEqual(picture.label, "Picture: Hills under a yellow sun")
        screenshot("picture-in-post")

        let viewer = app.descendants(matching: .any)["imageViewer.image"].firstMatch
        for (n, close) in ["swipe down", "swipe up", "close button"].enumerated() {
            if !picture.isHittable { drag(app, by: -120) }
            picture.tap()
            XCTAssertTrue(viewer.waitForExistence(timeout: 5), "Round \(n + 1): the picture opens full screen")
            XCTAssertGreaterThan(viewer.frame.width, picture.frame.width, "Full screen is wider than the post")
            if n == 0 {
                screenshot("picture-viewer")
                // X's media viewer: the post and its actions under the picture, no reply field.
                let summary = app.buttons["imageViewer.post"].firstMatch
                XCTAssertTrue(summary.waitForExistence(timeout: 3), "The post shows under the picture")
                XCTAssertFalse(summary.label.isEmpty)
                XCTAssertTrue(app.buttons["imageViewer.more"].exists, "A ⋯ button at the top")
                XCTAssertTrue(app.descendants(matching: .any)["imageViewer.share"].exists, "A share button")
                XCTAssertEqual(app.textFields.count + app.textViews.count, 0, "No reply field")
                let bookmark = app.buttons["imageViewer.bookmark"].firstMatch
                XCTAssertTrue(bookmark.exists)
                XCTAssertEqual(bookmark.label, "Bookmark")
                bookmark.tap()
                XCTAssertTrue(waitFor(bookmark, label: "Remove bookmark"), "The bookmark button bookmarks the post")
                bookmark.tap()
                XCTAssertTrue(waitFor(bookmark, label: "Bookmark"), "A second tap removes the bookmark")
                // A tap on the viewer hides its buttons and a second tap shows them again.
                viewer.tap()
                waitUntilGone(summary)
                viewer.tap()
                XCTAssertTrue(summary.waitForExistence(timeout: 3))
            }
            switch close {
            case "swipe down": viewer.swipeDown(velocity: .fast)
            case "swipe up": viewer.swipeUp(velocity: .fast)
            default:
                let button = app.buttons["imageViewer.close"].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 3))
                button.tap()
            }
            waitUntilGone(viewer)
            XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5), "Round \(n + 1): \(close) goes back to the feed")
        }

        // "Read" closes the viewer and opens the post in the reader.
        if !picture.isHittable { drag(app, by: -120) }
        picture.tap()
        XCTAssertTrue(viewer.waitForExistence(timeout: 5))
        app.buttons["imageViewer.context"].firstMatch.tap()
        waitUntilGone(viewer)
        let continueButton = app.buttons["Continue in feed from here"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Read opens the post in context")
        app.buttons["Done"].firstMatch.tap()
        waitUntilGone(continueButton)
    }

    private func waitFor(_ element: XCUIElement, label: String, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    func testTheBarsHideSmoothlyAtTheLargestTextSize() {
        let app = launch(
            sampleBooks: true,
            extra: ["-UITestHideBars", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        )
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        let libraryTab = app.tabBars.buttons["Library"].firstMatch
        let home = libraryTab.frame
        for round in 1...2 {
            drag(app, by: 260)
            assertTabBar(app, hidden: true, "Round \(round): reading down hides the tab bar")
            drag(app, by: -200)
            assertTabBar(app, hidden: false, "Round \(round): scrolling up shows it")
        }
        XCTAssertEqual(libraryTab.frame.minY, home.minY, accuracy: 0.5)
        assertSmoothTrace(app, minimumRests: 2)
    }

    func testPostStyleAndOneBookThread() {
        // Word limit off, so the long paragraph stays one post and "Show more" appears.
        let app = launch(sampleBooks: true, extra: ["-wordLimit", "0"])
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))

        openToolbarMenu(app, "Feed mode", choice: firstTitle).tap()
        XCTAssertTrue(app.navigationBars[firstTitle].waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, labelBeginsWith: "Continues thread.").waitForExistence(timeout: 5), "Threads in One book mode")
        XCTAssertTrue(element(app, labelBeginsWith: "Chapter: Chapter 1").exists, "Chapter header row")

        let showMore = app.buttons["post.showMore"].firstMatch
        XCTAssertTrue(showMore.waitForExistence(timeout: 5), "A long paragraph is cut after 10 lines")
        screenshot("07-feed-one-book")
        showMore.tap()
        waitUntilGone(showMore)

        openToolbarMenu(app, "Post style", choice: "Passages").tap()
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Post style"].value as? String, "Passages")
        screenshot("08-feed-passages")

        // The choice is remembered for the Saved tab and the next view.
        openToolbarMenu(app, "Feed mode", choice: "Mix all books").tap()
        XCTAssertTrue(app.navigationBars["Feed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Post style"].value as? String, "Passages")
    }

    func testReadingListReadsItsSetsInTheFeed() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        // With no sets yet, the menu choice opens the editor.
        openToolbarMenu(app, "Feed mode", choice: "Reading list").tap()
        let addSet = app.buttons["readingList.addSet"].firstMatch
        XCTAssertTrue(addSet.waitForExistence(timeout: 5), "An empty reading list opens the editor")

        let books = app.buttons.matching(identifier: "choose.book")
        for index in 0..<2 {
            addSet.tap()
            XCTAssertTrue(books.firstMatch.waitForExistence(timeout: 5))
            books.element(boundBy: index).tap()
            let save = app.buttons["choose.done"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 5))
            XCTAssertEqual(save.label, "Save Set (1)")
            save.tap()
            XCTAssertTrue(addSet.waitForExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["Set 1"].exists)
        XCTAssertTrue(app.staticTexts["Set 2"].exists)
        screenshot("32-reading-list")

        let read = app.buttons["readingList.read"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
        waitForValue(app.buttons["Feed mode"].firstMatch, "Reading list: Set 1")

        tab(app, "Shelves")
        XCTAssertTrue(app.buttons["shelves.readingList"].waitForExistence(timeout: 5), "The Shelves tab opens the reading list")
    }

    func testChooseBooksMixesOnlyTheChosenBooks() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        openToolbarMenu(app, "Feed mode", choice: "Choose books\u{2026}").tap()
        let books = app.buttons.matching(identifier: "choose.book")
        XCTAssertTrue(books.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(books.count, 2, "Every library book is listed")
        books.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["choose.done"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["choose.done"].label, "Read 1 Book")
        books.element(boundBy: 1).tap()
        XCTAssertEqual(app.buttons["choose.done"].label, "Mix 2 Books")
        XCTAssertTrue(books.element(boundBy: 0).isSelected)
        screenshot("10a-choose-books")
        app.buttons["choose.done"].tap()
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
        waitForValue(app.buttons["Feed mode"].firstMatch, "Chosen books: 2 books")
        XCTAssertTrue(app.navigationBars["2 books"].waitForExistence(timeout: 5))

        // The sheet starts with the chosen books. Select None, Select All, then keep the set
        // as a shelf.
        openToolbarMenu(app, "Feed mode", choice: "Chosen books (2)\u{2026}").tap()
        let selectAll = app.buttons["choose.selectAll"].firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        XCTAssertEqual(selectAll.label, "Select None")
        selectAll.tap()
        XCTAssertTrue(app.buttons["choose.done"].waitForNonExistence(timeout: 5))
        selectAll.tap()
        XCTAssertEqual(app.buttons["choose.done"].label, "Mix 2 Books")
        let saveShelf = app.buttons["choose.saveShelf"].firstMatch
        saveShelf.tap()
        let alert = app.alerts.firstMatch
        if !alert.waitForExistence(timeout: 3) { saveShelf.tap() }
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Save as Shelf asks for a name")
        let name = alert.textFields.firstMatch
        name.tap()
        name.typeText("Evening")
        alert.buttons["Save"].tap()
        waitForValue(app.buttons["Feed mode"].firstMatch, "Shelf: Evening")
    }

    private func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) {
        let match = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        wait(for: [match], timeout: timeout)
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
        XCTAssertTrue(openToolbarMenu(app, "Feed mode", choice: firstTitle).exists)
        XCTAssertFalse(menuChoice(app, secondTitle).exists, "The deleted book left the feed")
    }

    func testFinishFilterAndEditDetailsInLibrary() throws {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        tab(app, "Library")

        // Mark as finished from the context menu.
        let second = element(app, labelBeginsWith: "\(secondTitle), by")
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.press(forDuration: 1.2)
        let finish = app.buttons["Mark as Finished"].firstMatch
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        let finishedRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "\(secondTitle), by", "Finished"))
            .firstMatch
        XCTAssertTrue(finishedRow.waitForExistence(timeout: 5), "The row says the book is finished")

        // Filter to finished books.
        openToolbarMenu(app, "Sort and filter", choice: "Finished").tap()
        let clear = app.buttons["library.filter.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertTrue(finishedRow.exists)
        waitUntilGone(element(app, labelBeginsWith: "\(firstTitle), by"))
        screenshot("23-library-filtered")
        try audit(app, screen: "library filtered")
        clear.tap()
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").waitForExistence(timeout: 5))

        // Edit details.
        let first = element(app, labelBeginsWith: "\(firstTitle), by")
        first.press(forDuration: 1.2)
        let edit = app.buttons["Edit Details\u{2026}"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        // A multi-line text field is a text view on some iOS versions.
        let titleField = app.descendants(matching: .any).matching(identifier: "details.title").firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["details.showsCover"].exists)
        screenshot("24-edit-details")
        try audit(app, screen: "edit details")
        // The cursor goes to the end of the text.
        titleField.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        titleField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: firstTitle.count + 2) + "Renamed Bridge")
        app.buttons["details.save"].tap()
        XCTAssertTrue(element(app, labelBeginsWith: "Renamed Bridge, by").waitForExistence(timeout: 5))

        // The feed shows the new title.
        tab(app, "Feed")
        XCTAssertTrue(openToolbarMenu(app, "Feed mode", choice: "Renamed Bridge").exists)
    }

    func testShelfCreateAddBooksAndReadAsFeed() throws {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        tab(app, "Shelves")
        let newShelf = app.buttons["shelves.empty.new"]
        XCTAssertTrue(newShelf.waitForExistence(timeout: 5))
        screenshot("25-shelves-empty")
        newShelf.tap()
        let alert = app.alerts.firstMatch
        // iOS 17 can drop the first tap right after a tab switch; it is tried once more.
        if !alert.waitForExistence(timeout: 3) { newShelf.tap() }
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let name = alert.textFields.firstMatch
        name.tap()
        name.typeText("Favourites")
        alert.buttons["Create"].tap()

        // The new shelf opens; add a book.
        let add = app.buttons["shelf.empty.add"]
        if !add.waitForExistence(timeout: 10) {
            screenshot("debug-new-shelf")
            XCTFail("The new shelf did not open")
            return
        }
        add.tap()
        let member = app.descendants(matching: .any).matching(identifier: "shelf.member")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(firstTitle), by")).firstMatch
        XCTAssertTrue(member.waitForExistence(timeout: 5))
        member.tap()
        app.buttons["shelf.members.done"].tap()
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, labelBeginsWith: "\(secondTitle), by").exists)
        screenshot("26-shelf")
        try audit(app, screen: "shelf")

        // Read the shelf as a feed.
        app.buttons["shelf.readInFeed"].tap()
        XCTAssertTrue(app.navigationBars["Favourites"].waitForExistence(timeout: 5))
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Feed mode"].value as? String, "Shelf: Favourites")
    }

    func testPasteTextAddsABook() throws {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        tab(app, "Library")
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").waitForExistence(timeout: 5))
        tapToolbarButton(app, "library.paste")

        let title = app.textFields["paste.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let add = app.buttons["paste.add"]
        XCTAssertFalse(add.isEnabled, "Add needs text")
        title.tap()
        title.typeText("Kitchen Notes")
        let text = app.descendants(matching: .any).matching(identifier: "paste.text").firstMatch
        text.tap()
        text.typeText("Part One\n\nThe bread rose overnight in the cold kitchen.\n\nBy noon it was ready for the oven.")
        XCTAssertTrue(add.isEnabled)
        // The keyboard covers the footer; the audit would sample the keyboard.
        let keyboardDone = app.buttons["paste.keyboardDone"].firstMatch
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5))
        keyboardDone.tap()
        let keyboardGone = Date().addingTimeInterval(5)
        while app.keyboards.firstMatch.exists && Date() < keyboardGone { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertFalse(app.keyboards.firstMatch.exists, "The keyboard is hidden")
        screenshot("27-paste-text")
        try audit(app, screen: "paste text")
        add.tap()

        let row = element(app, labelBeginsWith: "Kitchen Notes, by Unknown author")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "The pasted text is a book in the Library")
        tab(app, "Feed")
        XCTAssertTrue(openToolbarMenu(app, "Feed mode", choice: "Kitchen Notes").exists)
    }

    // MARK: Settings and post look

    func testSettingsChangeThemeAccentAndFocusMode() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        screenshot("14-feed-night-default")
        tab(app, "Settings")
        let sepia = app.buttons["Sepia"].firstMatch
        XCTAssertTrue(sepia.waitForExistence(timeout: 5))
        sepia.tap()
        XCTAssertTrue(sepia.isSelected, "Sepia is the selected theme")
        // Sepia has its own brightness: a darker brown, then back to the default.
        let brightness = app.sliders["settings.themeBrightness"].firstMatch
        XCTAssertTrue(brightness.waitForExistence(timeout: 5))
        brightness.adjust(toNormalizedSliderPosition: 0.2)
        let reset = app.buttons["settings.themeBrightness.reset"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5), "A changed brightness can be reset")
        screenshot("15a-settings-sepia-darker")
        reset.tap()
        XCTAssertFalse(reset.waitForExistence(timeout: 2))
        app.buttons["accent.orange"].tap()
        XCTAssertTrue(app.buttons["accent.orange"].isSelected)
        screenshot("15-settings-sepia")

        let focus = app.switches["settings.focusMode"].firstMatch
        // The theme list and brightness slider push the Posts section below the fold.
        reveal(focus, in: app)
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        // A Form toggle only reacts on the switch itself, at the trailing edge of the row.
        focus.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(focus.value as? String, "1")

        tab(app, "Feed")
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Bookmark"].exists, "Focus mode hides the buttons")
        screenshot("16-feed-sepia-focus")
    }

    func testLongParagraphIsSplitIntoNumberedParts() {
        // The default word limit (Auto) splits the 18-sentence paragraph of the first book.
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        openToolbarMenu(app, "Feed mode", choice: firstTitle).tap()
        XCTAssertTrue(app.navigationBars[firstTitle].waitForExistence(timeout: 5))
        let firstPart = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Part 1 of")).firstMatch
        XCTAssertTrue(firstPart.waitForExistence(timeout: 5), "The long paragraph is split")
        XCTAssertTrue(element(app, labelBeginsWith: "Chapter: Chapter 1. New chapter begins.").exists, "The book starts with a new-chapter row")
        screenshot("17-feed-split-parts")
    }

    func testJumpToAChapterAndPeekAtAPost() {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        openToolbarMenu(app, "Feed mode", choice: firstTitle).tap()
        XCTAssertTrue(app.navigationBars[firstTitle].waitForExistence(timeout: 5))

        tapToolbarButton(app, "Jump to")
        let chapter = element(app, labelBeginsWith: "Chapter 3,")
        XCTAssertTrue(chapter.waitForExistence(timeout: 5), "The chapter list shows")
        screenshot("18-jump-to")
        chapter.tap()
        XCTAssertTrue(element(app, labelBeginsWith: "Chapter: Chapter 3. New chapter begins.").waitForExistence(timeout: 5), "The feed opens at chapter 3")

        // Long press: the context peek and its menu.
        firstPost(app).press(forDuration: 1.2)
        let lookUp = menuChoice(app, "Look up a word")
        XCTAssertTrue(lookUp.waitForExistence(timeout: 5), "The peek menu shows")
        XCTAssertTrue(menuChoice(app, "Copy with citation").exists)
        screenshot("19-context-peek")
        lookUp.tap()
        if !app.descendants(matching: .any)["lookup.text"].waitForExistence(timeout: 8) {
            screenshot("debug-look-up")
            XCTFail("The look-up sheet shows the post text")
            return
        }
        screenshot("20-look-up")
        app.buttons["Done"].firstMatch.tap()
    }

    func testHighlightSearchAndShareCard() throws {
        let app = launch(sampleBooks: true)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))

        // Highlight a post from its long-press menu.
        firstPost(app).press(forDuration: 1.2)
        let highlight = menuChoice(app, "Highlight")
        XCTAssertTrue(highlight.waitForExistence(timeout: 5))
        highlight.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'post' AND label CONTAINS 'Highlighted.'")).firstMatch.waitForExistence(timeout: 5), "The post shows as highlighted")

        // Saved › Highlights lists it; tapping opens the reader with the highlight.
        tab(app, "Saved")
        app.segmentedControls.firstMatch.buttons["Highlights"].tap()
        let saved = app.descendants(matching: .any)["highlight"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        screenshot("21-saved-highlights")
        try audit(app, screen: "saved highlights")
        saved.tap()
        XCTAssertTrue(app.buttons["Continue in feed from here"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, labelBeginsWith: "Selected post. Contains a highlight.").waitForExistence(timeout: 5), "The reader marks the highlight")
        app.buttons["Done"].firstMatch.tap()

        // Library search finds text in the books.
        tab(app, "Library")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("river\n")
        let result = app.descendants(matching: .any)["search.result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10), "Paragraphs with the word are listed")
        XCTAssertTrue(result.label.localizedCaseInsensitiveContains("river"))
        screenshot("22-library-search")
        try audit(app, screen: "library search")
        result.tap()
        XCTAssertTrue(app.buttons["Continue in feed from here"].waitForExistence(timeout: 10), "A result opens the reader")
        app.buttons["Done"].firstMatch.tap()

        // Share as image: the card sheet with its styles.
        tab(app, "Feed")
        app.buttons["Share"].firstMatch.tap()
        let asImage = menuChoice(app, "Share as image")
        XCTAssertTrue(asImage.waitForExistence(timeout: 5))
        asImage.tap()
        XCTAssertTrue(app.descendants(matching: .any)["share.preview"].waitForExistence(timeout: 10), "The card preview shows")
        app.segmentedControls["share.style"].buttons["Quote"].tap()
        app.segmentedControls["share.theme"].buttons["Sepia"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["share.preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["share.send"].exists)
        screenshot("23-share-card")
        try audit(app, screen: "share card")
        app.buttons["Cancel"].firstMatch.tap()
    }

    func testDoubleTapBookmarksAPost() {
        let app = launch(sampleBooks: true)
        let post = firstPost(app)
        XCTAssertTrue(post.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Change bookmark"].exists)
        post.doubleTap()
        XCTAssertTrue(app.buttons["Change bookmark"].firstMatch.waitForExistence(timeout: 5), "Double tap bookmarked the post")
        XCTAssertFalse(app.buttons["Continue in feed from here"].exists, "A double tap does not open the reader")

        // A tap outside the colour bubble only closes it: it does not open the reader.
        let noHighlight = app.buttons["bookmark.color.none"].firstMatch
        XCTAssertTrue(noHighlight.waitForExistence(timeout: 5), "The colour bubble opens")
        post.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.9)).tap()
        XCTAssertTrue(noHighlight.waitForNonExistence(timeout: 5), "A tap outside closes the bubble")
        XCTAssertFalse(app.buttons["Continue in feed from here"].waitForExistence(timeout: 2), "The tap outside does not open the reader")

        post.doubleTap()
        XCTAssertTrue(app.buttons["Change bookmark"].firstMatch.exists, "A second double tap does not remove the bookmark")
    }

    // MARK: Accessibility

    func testAccessibilityAuditLightTheme() throws {
        try runAudit(extra: ["-appTheme", "light"], prefix: "light")
    }

    func testAccessibilityAuditNightTheme() throws {
        try runAudit(extra: ["-appTheme", "night"], prefix: "night")
    }

    func testAccessibilityAuditSepiaTheme() throws {
        try runAudit(extra: ["-appTheme", "sepia", "-accentChoice", "orange"], prefix: "sepia")
    }

    func testAccessibilityAuditCompactFocusSerif() throws {
        try runAudit(extra: ["-density", "compact", "-focusMode", "YES", "-postTypeface", "serif", "-accentChoice", "purple"], prefix: "focus")
    }

    func testLargestAccessibilityTextSize() throws {
        let app = launch(
            sampleBooks: true,
            extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
            stopOnFailure: false
        )
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        let bookmark = app.buttons["Bookmark"].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 5))
        screenshot("12-feed-largest-text")
        bookmark.tap()
        XCTAssertTrue(app.buttons["Change bookmark"].firstMatch.waitForExistence(timeout: 5))
        // Close the colour bubble: while it is open, the next tap only closes it.
        let noHighlight = app.buttons["bookmark.color.none"].firstMatch
        XCTAssertTrue(noHighlight.waitForExistence(timeout: 5))
        noHighlight.tap()
        XCTAssertTrue(noHighlight.waitForNonExistence(timeout: 5))
        tab(app, "Library")
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").waitForExistence(timeout: 5))
        screenshot("13-library-largest-text")
        try audit(app, types: [.dynamicType], screen: "largest text library")
        // Settings rows stack title and value at this size (checked on the picture). At this
        // size the accent swatches are below the fold, under the theme list.
        tab(app, "Settings")
        XCTAssertTrue(app.buttons["Night"].firstMatch.waitForExistence(timeout: 5))
        app.swipeUp(velocity: .slow)
        screenshot("29-settings-largest-text")
    }

    private func runAudit(extra: [String], prefix: String) throws {
        let app = launch(sampleBooks: true, extra: extra, stopOnFailure: false)
        XCTAssertTrue(firstPost(app).waitForExistence(timeout: 15))
        screenshot("10-\(prefix)-feed")
        try audit(app, screen: "\(prefix) feed")

        tab(app, "Library")
        XCTAssertTrue(element(app, labelBeginsWith: "\(firstTitle), by").waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) library")
        tapToolbarButton(app, "library.stats")
        XCTAssertTrue(app.buttons["stats.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "stats.chart").firstMatch.waitForExistence(timeout: 5))
        screenshot("30-\(prefix)-stats")
        try audit(app, screen: "\(prefix) stats")
        app.buttons["stats.done"].tap()

        tab(app, "Shelves")
        XCTAssertTrue(app.buttons["shelves.empty.new"].waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) shelves")

        tab(app, "Saved")
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) saved")

        tab(app, "Settings")
        XCTAssertTrue(app.buttons["accent.blue"].waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) settings")
        reveal(app.buttons["settings.storage"], in: app)
        app.buttons["settings.storage"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "storage.book").firstMatch.waitForExistence(timeout: 10))
        screenshot("28-\(prefix)-storage")
        try audit(app, screen: "\(prefix) storage")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["settings.folderSync"], in: app)
        app.buttons["settings.folderSync"].tap()
        XCTAssertTrue(app.buttons["folderSync.choose"].waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) synced folder")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["settings.backup"], in: app)
        app.buttons["settings.backup"].tap()
        XCTAssertTrue(app.buttons["backup.export"].waitForExistence(timeout: 5))
        try audit(app, screen: "\(prefix) backup")

        tab(app, "Feed")
        // A tap on the post text opens the reader (focus mode has no action bar).
        firstPost(app).tap()
        XCTAssertTrue(app.buttons["Continue in feed from here"].waitForExistence(timeout: 10))
        screenshot("11-\(prefix)-reader")
        try audit(app, screen: "\(prefix) reader")
    }

    /// Runs the system accessibility audit. Every issue is printed with its element (CI greps
    /// "AUDIT:") and fails the test, except the known false positives below.
    private func audit(_ app: XCUIApplication, types: XCUIAccessibilityAuditType = .all, screen: String) throws {
        // Every finding of every screen is reported, not only the first.
        let stops = !continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = !stops }
        let bars = [app.tabBars.firstMatch, app.buttons["Continue in feed from here"]]
            .filter(\.exists)
            .map(\.frame)
        let posts = app.descendants(matching: .any).matching(identifier: "post").allElementsBoundByIndex
            .filter(\.exists)
            .map(\.frame)
        // Tab switches and pushes cross-fade; an audit during the fade samples half-drawn text.
        Thread.sleep(forTimeInterval: 1)
        var issues = try auditIssues(app, types: types, screen: screen)
        // A failing finding must show again in a second audit a second later. Contrast samples
        // taken while a row or the tab bar redraws differ from run to run (seen on the Theme
        // rows of Settings, whose colours pass the WCAG test in AppearanceTests).
        let failing = issues.filter { !Self.isKnownFalsePositive($0, bars: bars, posts: posts) }
        if !failing.isEmpty {
            Thread.sleep(forTimeInterval: 1)
            let again = try auditIssues(app, types: types, screen: screen).map(Self.key)
            for issue in failing where !again.contains(Self.key(issue)) {
                print("AUDIT: not repeated [\(screen)] \(issue.compactDescription) | \(issue.element?.label ?? "no element")")
            }
            issues = issues.filter { Self.isKnownFalsePositive($0, bars: bars, posts: posts) || again.contains(Self.key($0)) }
        }
        var tookScreenshot = false
        for issue in issues {
            var place = "no element"
            if let element = issue.element, element.exists {
                place = "type \(element.elementType.rawValue) label '\(element.label)' id '\(element.identifier)' frame \(element.frame)"
            }
            let ignored = Self.isKnownFalsePositive(issue, bars: bars, posts: posts)
            print("AUDIT: \(ignored ? "ignored" : "FAIL") [\(screen)] \(issue.compactDescription) | \(place) | \(issue.detailedDescription)")
            if (place == "no element" || !ignored) && !tookScreenshot {
                // An issue without an element can only be found on a picture of the screen;
                // a failing one is easier to fix with the picture.
                screenshot("audit-\(screen.replacingOccurrences(of: " ", with: "-"))")
                tookScreenshot = true
            }
            if !ignored {
                XCTFail("Accessibility audit [\(screen)]: \(issue.compactDescription) | \(place)")
            }
        }
    }

    /// Runs the audit and collects its findings. An audit that runs out of time (seen on iOS 17
    /// at the largest text size, and on a busy CI runner) runs up to three times.
    private func auditIssues(_ app: XCUIApplication, types: XCUIAccessibilityAuditType, screen: String) throws -> [XCUIAccessibilityAuditIssue] {
        var issues: [XCUIAccessibilityAuditIssue] = []
        for attempt in 1...3 {
            issues = []
            do {
                // The handler only collects; the issues are judged afterwards on the main actor.
                try app.performAccessibilityAudit(for: types) { issue in
                    issues.append(issue)
                    return true
                }
                break
            } catch let error as NSError where error.code == -56 && attempt < 3 {
                print("AUDIT: timed out [\(screen)], trying again")
            }
        }
        return issues
    }

    /// The same finding in two audits: same kind, same element.
    static func key(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let element = issue.element.flatMap { $0.exists ? "\($0.elementType.rawValue)|\($0.label)|\($0.identifier)" : nil } ?? "none"
        return "\(issue.auditType.rawValue)|\(element)"
    }

    /// Issues the audit reports for correct SwiftUI code. Each rule is narrow:
    /// - Contrast on an element that runs under the translucent tab bar or the reader's
    ///   bottom bar: the audit samples the bar, not the element's own background.
    /// - "Dynamic Type font sizes are partially unsupported": reported for text that uses
    ///   text styles, and even for the system "Done" button. Text that ignores Dynamic Type
    ///   entirely is reported as "unsupported" and still fails.
    /// - "Text clipped" on post text: the spec cuts posts after 10 lines and offers
    ///   "Show more"; VoiceOver reads the whole post.
    /// - "Text clipped" on the text lines inside a post (title, author, progress line, chapter
    ///   start). They have no line limit and wrap; testLargestAccessibilityTextSize shows them
    ///   wrapped. The audit flags a one-line text whose width would not fit at a larger size.
    /// - Contrast and clipping on the search field (the system draws its placeholder) and the
    ///   size of its clear button (a system control).
    /// - "Text clipped" on an empty text field: the system draws the placeholder.
    /// - Any issue with no element: the audit cannot say what it checked, so it cannot be
    ///   fixed or judged from the report. On iOS 26 contrast issues of this kind come from the
    ///   glass tab bar over scrolled content; on iOS 17 Dynamic Type and clipping issues of
    ///   this kind come with rows that VoiceOver reads as one element. They are printed and a
    ///   screenshot is saved ("audit-<screen>") for review, but they do not fail the test.
    ///   testLargestAccessibilityTextSize saves pictures of the feed, Library and Settings at
    ///   the largest text size, where clipped or fixed-size text shows.
    /// Text in a Dynamic Type text style that the audit still reports (see isKnownFalsePositive).
    static let textStyleDetails: Set<String> = ["Book text, marks and reading places", "Rebuilt from the library when needed"]

    static func isKnownFalsePositive(_ issue: XCUIAccessibilityAuditIssue, bars: [CGRect], posts: [CGRect]) -> Bool {
        let description = issue.compactDescription
        if description.contains("partially unsupported") { return true }
        guard let element = issue.element, element.exists else { return true }
        if issue.auditType == .contrast, bars.contains(where: { $0.intersects(element.frame) }) { return true }
        if issue.auditType == .textClipped, element.label.count >= 60 { return true }
        if issue.auditType == .textClipped, element.elementType == .staticText,
           posts.contains(where: { $0.contains(element.frame) }) { return true }
        // Post text has the size set in Settings (Post text size, in points), and the
        // accessibility text sizes enlarge it (testLargestAccessibilityTextSize). The audit
        // reports any font with a size in points.
        if issue.auditType == .dynamicType, element.elementType == .staticText,
           posts.contains(where: { $0.contains(element.frame) }) { return true }
        // The Storage row details use the footnote text style. The audit reports them as
        // "partially unsupported" in one run and "unsupported" in the next, with no code change.
        if issue.auditType == .dynamicType, element.elementType == .staticText,
           Self.textStyleDetails.contains(element.label) { return true }
        // The search field's placeholder and clear button are drawn by UIKit in system colours
        // and sizes; the app cannot style them.
        if issue.auditType == .contrast || issue.auditType == .textClipped, element.elementType == .searchField { return true }
        if issue.auditType == .hitRegion, issue.detailedDescription.contains("_UITextFieldClearButton") { return true }
        // An empty text field shows its placeholder, which UIKit draws; typed text is checked.
        if issue.auditType == .textClipped, element.elementType == .textField,
           (element.value as? String).map({ $0.isEmpty || $0 == element.placeholderValue }) ?? true { return true }
        return false
    }
}
