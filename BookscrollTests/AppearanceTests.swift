import SwiftUI
import XCTest
@testable import Bookscroll

/// Settings defaults and storage, theme contrast, and the citation format.
final class AppearanceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AppearanceTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: Settings

    @MainActor
    func testDefaultsAreNightBlueComfortableSansWithDoubleTap() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.theme, .night)
        XCTAssertEqual(settings.theme.colorScheme, .dark)
        XCTAssertEqual(settings.accent, .blue)
        XCTAssertEqual(settings.density, .comfortable)
        XCTAssertEqual(settings.postTypeface, .sans)
        XCTAssertEqual(settings.readerTypeface, .serif)
        XCTAssertFalse(settings.focusMode)
        XCTAssertTrue(settings.doubleTapToLike)
    }

    @MainActor
    func testSettingsAreStoredAndReadBack() {
        let settings = AppSettings(defaults: defaults)
        settings.theme = .sepia
        settings.accent = .purple
        settings.density = .compact
        settings.postTypeface = .serif
        settings.readerTypeface = .sans
        settings.focusMode = true
        settings.doubleTapToLike = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.theme, .sepia)
        XCTAssertEqual(reloaded.theme.colorScheme, .light)
        XCTAssertEqual(reloaded.accent, .purple)
        XCTAssertEqual(reloaded.density, .compact)
        XCTAssertEqual(reloaded.postTypeface, .serif)
        XCTAssertEqual(reloaded.readerTypeface, .sans)
        XCTAssertTrue(reloaded.focusMode)
        XCTAssertFalse(reloaded.doubleTapToLike)
    }

    @MainActor
    func testLaunchArgumentStringsAndUnknownValues() {
        // Launch arguments arrive as strings ("-focusMode YES").
        defaults.set("YES", forKey: AppSettings.Key.focusMode)
        defaults.set("NO", forKey: AppSettings.Key.doubleTapToLike)
        defaults.set("mauve", forKey: AppSettings.Key.accent)
        defaults.set("neon", forKey: AppSettings.Key.theme)
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.focusMode)
        XCTAssertFalse(settings.doubleTapToLike)
        XCTAssertEqual(settings.accent, .blue, "Unknown values fall back to the default")
        XCTAssertEqual(settings.theme, .night)
    }

    // MARK: Contrast

    func testEveryAccentReadsAsTextOnEveryBackground() {
        for accent in AccentChoice.allCases {
            let (dark, light) = accent.hex
            XCTAssertGreaterThanOrEqual(PaletteHex.contrast(dark, PaletteHex.darkBackground), 4.5, "\(accent) on black")
            XCTAssertGreaterThanOrEqual(PaletteHex.contrast(dark, PaletteHex.darkSecondaryBackground), 4.5, "\(accent) on dark rows")
            XCTAssertGreaterThanOrEqual(PaletteHex.contrast(light, PaletteHex.lightBackground), 4.5, "\(accent) on white")
            XCTAssertGreaterThanOrEqual(PaletteHex.contrast(light, PaletteHex.lightSecondaryBackground), 4.5, "\(accent) on light rows")
            XCTAssertGreaterThanOrEqual(PaletteHex.contrast(light, PaletteHex.sepiaBackground), 4.5, "\(accent) on sepia")
            XCTAssertGreaterThanOrEqual(PaletteHex.contrast(light, PaletteHex.sepiaSecondaryBackground), 4.5, "\(accent) on sepia rows")
        }
    }

    func testThemeTextColoursReachAA() {
        let pairs: [(String, UInt32, [UInt32])] = [
            ("light primary", PaletteHex.lightPrimary, [PaletteHex.lightBackground, PaletteHex.lightSecondaryBackground, PaletteHex.lightHighlight]),
            ("light secondary", PaletteHex.lightSecondary, [PaletteHex.lightBackground, PaletteHex.lightSecondaryBackground]),
            ("dark primary", PaletteHex.darkPrimary, [PaletteHex.darkBackground, PaletteHex.darkSecondaryBackground, PaletteHex.darkHighlight]),
            ("dark secondary", PaletteHex.darkSecondary, [PaletteHex.darkBackground, PaletteHex.darkSecondaryBackground]),
            ("sepia primary", PaletteHex.sepiaPrimary, [PaletteHex.sepiaBackground, PaletteHex.sepiaSecondaryBackground, PaletteHex.sepiaHighlight]),
            ("sepia secondary", PaletteHex.sepiaSecondary, [PaletteHex.sepiaBackground, PaletteHex.sepiaSecondaryBackground, PaletteHex.sepiaHighlight]),
        ]
        for (name, text, backgrounds) in pairs {
            for background in backgrounds {
                XCTAssertGreaterThanOrEqual(PaletteHex.contrast(text, background), 4.5, "\(name) on \(String(background, radix: 16))")
            }
        }
        XCTAssertEqual(PaletteHex.contrast(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
    }

    // MARK: Citation

    func testCitationIncludesTitleAuthorChapterAndPercent() {
        XCTAssertEqual(
            ShareFormatter.citation(text: "The river ran fast.", title: "The Stone Bridge", author: "Ada Lane", chapter: "Chapter 2", percent: 42),
            "\u{201C}The river ran fast.\u{201D}\n\u{2014} The Stone Bridge, Ada Lane \u{00B7} Chapter 2 \u{00B7} 42%"
        )
        XCTAssertEqual(
            ShareFormatter.citation(text: "No chapters.", title: "Notes", author: "Ben Ito", chapter: "", percent: 0),
            "\u{201C}No chapters.\u{201D}\n\u{2014} Notes, Ben Ito \u{00B7} 0%"
        )
    }
}
