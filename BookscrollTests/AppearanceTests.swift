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
        XCTAssertEqual(settings.postTextSize, 16.5)
        XCTAssertFalse(settings.focusMode)
        XCTAssertTrue(settings.doubleTapToBookmark)
    }

    @MainActor
    func testSettingsAreStoredAndReadBack() {
        let settings = AppSettings(defaults: defaults)
        settings.theme = .sepia
        settings.accent = .purple
        settings.density = .compact
        settings.postTypeface = .serif
        settings.readerTypeface = .georgia
        settings.postTextSize = 18.5
        settings.focusMode = true
        settings.doubleTapToBookmark = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.theme, .sepia)
        XCTAssertEqual(reloaded.theme.colorScheme, .light)
        XCTAssertEqual(reloaded.accent, .purple)
        XCTAssertEqual(reloaded.density, .compact)
        XCTAssertEqual(reloaded.postTypeface, .serif)
        XCTAssertEqual(reloaded.readerTypeface, .georgia)
        XCTAssertEqual(reloaded.postTextSize, 18.5)
        XCTAssertTrue(reloaded.focusMode)
        XCTAssertFalse(reloaded.doubleTapToBookmark)
    }

    func testPostTextSizeStepsByHalfPoints() {
        XCTAssertEqual(PostTextSize.clamped(17.2), 17)
        XCTAssertEqual(PostTextSize.clamped(17.3), 17.5)
        XCTAssertEqual(PostTextSize.clamped(17.75), 18)
        XCTAssertEqual(PostTextSize.clamped(2), PostTextSize.range.lowerBound)
        XCTAssertEqual(PostTextSize.clamped(99), PostTextSize.range.upperBound)
        XCTAssertEqual(PostTextSize.clamped(.nan), PostTextSize.standard)
        XCTAssertEqual(PostTextSize.parse("17.5"), 17.5)
        XCTAssertEqual(PostTextSize.parse(" 17,5 "), 17.5, "A comma works as the decimal separator")
        XCTAssertEqual(PostTextSize.parse("18"), 18)
        XCTAssertNil(PostTextSize.parse(""))
        XCTAssertNil(PostTextSize.parse("big"))
        XCTAssertEqual(PostTextSize.format(17), 17.formatted())
        XCTAssertEqual(PostTextSize.format(17.5), 17.5.formatted(.number.precision(.fractionLength(1))))
        XCTAssertEqual(PostTextSize.lineHeight(for: 16.5), 20.625, accuracy: 0.001, "The X app: 20.6 pt lines")
    }

    // MARK: Fonts

    func testTenReadingFontsWithTheXStyleFirst() {
        XCTAssertEqual(Typeface.allCases.count, 10)
        XCTAssertEqual(Typeface.allCases.first, .sans)
        XCTAssertEqual(Set(Typeface.allCases.map(\.title)).count, 10, "Every font has its own name")
        XCTAssertEqual(Typeface.sans.design, .default)
        XCTAssertEqual(Typeface.serif.design, .serif)
        XCTAssertNil(Typeface.sans.faceNames)
        XCTAssertNil(Typeface.serif.faceNames)
    }

    /// Every named face ships with iOS: the font is not replaced by the system font.
    func testEveryNamedFontIsInstalled() throws {
        for typeface in Typeface.allCases {
            guard let names = typeface.faceNames else { continue }
            for name in [names.regular, names.bold] {
                let font = try XCTUnwrap(UIFont(name: name, size: 17), "\(typeface): \(name) is missing")
                XCTAssertEqual(font.fontName, name)
            }
            XCTAssertEqual(typeface.uiFont(size: 17).fontName, names.regular)
            XCTAssertEqual(typeface.uiFont(size: 17, bold: true).fontName, names.bold)
            XCTAssertEqual(typeface.uiFont(textStyle: .body).fontName, names.regular)
        }
        XCTAssertEqual(Typeface.sans.uiFont(size: 16.5).pointSize, 16.5)
    }

    @MainActor
    func testFontsNoLongerOfferedFallBackToTheDefaults() {
        defaults.set("mono", forKey: AppSettings.Key.postTypeface)
        defaults.set("rounded", forKey: AppSettings.Key.readerTypeface)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.postTypeface, .sans)
        XCTAssertEqual(settings.readerTypeface, .serif)
    }

    @MainActor
    func testStoredPostTextSizeIsRoundedAndClamped() {
        defaults.set(17.3, forKey: AppSettings.Key.postTextSize)
        XCTAssertEqual(AppSettings(defaults: defaults).postTextSize, 17.5)
        defaults.set("500", forKey: AppSettings.Key.postTextSize)
        XCTAssertEqual(AppSettings(defaults: defaults).postTextSize, PostTextSize.range.upperBound)
    }

    @MainActor
    func testLaunchArgumentStringsAndUnknownValues() {
        // Launch arguments arrive as strings ("-focusMode YES").
        defaults.set("YES", forKey: AppSettings.Key.focusMode)
        defaults.set("NO", forKey: AppSettings.Key.doubleTapToBookmark)
        defaults.set("mauve", forKey: AppSettings.Key.accent)
        defaults.set("neon", forKey: AppSettings.Key.theme)
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.focusMode)
        XCTAssertFalse(settings.doubleTapToBookmark)
        XCTAssertEqual(settings.accent, .blue, "Unknown values fall back to the default")
        XCTAssertEqual(settings.theme, .night)
    }

    // MARK: Themes and brightness

    @MainActor
    func testThemesAndTheirColourSchemes() {
        XCTAssertEqual(AppTheme.allCases, [.night, .light, .sepia, .darkSepia, .sage, .dusk, .system])
        XCTAssertEqual(AppTheme.allCases.filter { $0.colorScheme == .dark }, [.night, .darkSepia, .dusk])
        XCTAssertEqual(AppTheme.allCases.filter { $0.colorScheme == .light }, [.light, .sepia, .sage])
        XCTAssertNil(AppTheme.system.colorScheme)
        XCTAssertFalse(AppTheme.system.hasBrightness)
    }

    /// The default brightness of Night, Light and Sepia gives the colours of earlier versions.
    func testDefaultBrightnessKeepsTheEarlierColours() {
        XCTAssertEqual(AppTheme.night.palette(brightness: AppTheme.night.defaultBrightness), ThemePalette.night.readable())
        XCTAssertEqual(AppTheme.light.palette(brightness: AppTheme.light.defaultBrightness), ThemePalette.light.readable())
        XCTAssertEqual(AppTheme.sepia.palette(brightness: AppTheme.sepia.defaultBrightness), ThemePalette.sepia.readable())
        for (palette, name) in [(ThemePalette.night, "night"), (.light, "light"), (.sepia, "sepia")] {
            let readable = palette.readable()
            var withoutAccents = readable
            withoutAccents.accents = []
            XCTAssertEqual(withoutAccents, palette, "\(name): no colour had to change")
        }
        let night = AppTheme.night.palette(brightness: 0)
        XCTAssertEqual(night.background, 0x000000)
        XCTAssertEqual(night.accent(.blue), AccentChoice.blue.hex.dark)
        XCTAssertEqual(AppTheme.light.palette(brightness: 1).accent(.yellow), AccentChoice.yellow.hex.light)
    }

    func testBrightnessGoesFromDarkToLight() {
        func luminance(_ hex: UInt32) -> Double { PaletteHex.contrast(hex, 0x000000) }
        for theme in AppTheme.allCases where theme.hasBrightness {
            let samples = stride(from: 0.0, through: 1.0, by: 0.1).map { luminance(theme.palette(brightness: $0).background) }
            XCTAssertEqual(samples, samples.sorted(), "\(theme): each step is at least as light as the one before")
            XCTAssertGreaterThan(samples.last! - samples.first!, 0.3, "\(theme): the slider makes a visible change")
            XCTAssertEqual(theme.palette(brightness: -3), theme.palette(brightness: 0))
            XCTAssertEqual(theme.palette(brightness: 9), theme.palette(brightness: 1))
            XCTAssertEqual(theme.palette(brightness: .nan), theme.palette(brightness: theme.defaultBrightness))
        }
    }

    /// Every theme at every brightness: text 7:1 (primary) and 4.5:1 (secondary, accents),
    /// primary text 7:1 on highlights and markers, icons 3:1.
    func testEveryThemeIsReadableAtEveryBrightness() {
        for theme in AppTheme.allCases where theme.hasBrightness {
            for step in 0...20 {
                let brightness = Double(step) / 20
                let palette = theme.palette(brightness: brightness)
                let place = "\(theme) at \(Int(brightness * 100))%"
                XCTAssertEqual(palette.isDark, theme.isDark, place)
                for background in [palette.background, palette.secondaryBackground] {
                    XCTAssertGreaterThanOrEqual(PaletteHex.contrast(palette.primary, background), 7, "\(place): primary text")
                    XCTAssertGreaterThanOrEqual(PaletteHex.contrast(palette.secondary, background), 4.5, "\(place): secondary text")
                    for accent in AccentChoice.allCases {
                        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(palette.accent(accent), background), 4.5, "\(place): \(accent)")
                    }
                    for icon in [palette.yellowIcon, palette.redIcon, palette.blueIcon] {
                        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(icon, background), 3, "\(place): icon \(String(icon, radix: 16))")
                    }
                }
                for marker in [palette.highlight, palette.marker, palette.redMarker, palette.blueMarker] {
                    XCTAssertGreaterThanOrEqual(PaletteHex.contrast(palette.primary, marker), 7, "\(place): text on \(String(marker, radix: 16))")
                }
            }
        }
    }

    @MainActor
    func testEachThemeKeepsItsOwnBrightness() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.brightness(for: .sepia), AppTheme.sepia.defaultBrightness)
        settings.setBrightness(0.3, for: .sepia)
        settings.setBrightness(0.9, for: .dusk)
        settings.setBrightness(7, for: .light)
        settings.setBrightness(0.5, for: .system)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.brightness(for: .sepia), 0.3)
        XCTAssertEqual(reloaded.brightness(for: .dusk), 0.9)
        XCTAssertEqual(reloaded.brightness(for: .light), 1, "Kept in 0...1")
        XCTAssertEqual(reloaded.brightness(for: .night), AppTheme.night.defaultBrightness)
        XCTAssertNil(reloaded.themeBrightness[AppTheme.system.rawValue], "System has no brightness")
        reloaded.resetBrightness(for: .sepia)
        XCTAssertEqual(AppSettings(defaults: defaults).brightness(for: .sepia), AppTheme.sepia.defaultBrightness)
    }

    func testMixAndReadable() {
        XCTAssertEqual(PaletteHex.mix(0x000000, 0xFFFFFF, 0), 0x000000)
        XCTAssertEqual(PaletteHex.mix(0x000000, 0xFFFFFF, 1), 0xFFFFFF)
        XCTAssertEqual(PaletteHex.mix(0x000000, 0xFF8040, 0.5), 0x804020)
        XCTAssertEqual(PaletteHex.readable(0x0F1419, on: [0xFFFFFF], target: 7, toward: 0x000000), 0x0F1419, "Already readable: unchanged")
        let fixed = PaletteHex.readable(0x9076FF, on: [0x2C2F33], target: 4.5, toward: 0xFFFFFF)
        XCTAssertGreaterThanOrEqual(PaletteHex.contrast(fixed, 0x2C2F33), 4.5)
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
