import SwiftUI
import UIKit

/// Every colour of one theme at one brightness, as sRGB hex. Build one with
/// `AppTheme.palette(brightness:)`, which also makes every text colour readable.
struct ThemePalette: Equatable {
    var isDark: Bool
    var background: UInt32
    /// Grouped rows (Settings) and cards.
    var secondaryBackground: UInt32
    var primary: UInt32
    var secondary: UInt32
    var separator: UInt32
    var threadLine: UInt32
    /// Background of the tapped post in the reader.
    var highlight: UInt32
    /// Background of the reader's own highlights and of yellow bookmarks.
    var marker: UInt32
    var redMarker: UInt32
    var blueMarker: UInt32
    var yellowIcon: UInt32
    var redIcon: UInt32
    var blueIcon: UInt32
    /// The accent shades, in `AccentChoice.allCases` order. Set by `readable()`.
    var accents: [UInt32] = []

    /// The accent shade for this palette: the accent's own shade, made lighter (dark themes)
    /// or darker (light themes) only as much as it needs to reach 4.5:1.
    func accent(_ choice: AccentChoice) -> UInt32 {
        let index = AccentChoice.allCases.firstIndex(of: choice) ?? 0
        if accents.indices.contains(index) { return accents[index] }
        return isDark ? choice.hex.dark : choice.hex.light
    }

    /// The colours `t` of the way from `a` to `b` (0 is `a`, 1 is `b`).
    static func mixed(_ a: ThemePalette, _ b: ThemePalette, _ t: Double) -> ThemePalette {
        func mix(_ key: KeyPath<ThemePalette, UInt32>) -> UInt32 { PaletteHex.mix(a[keyPath: key], b[keyPath: key], t) }
        return ThemePalette(
            isDark: a.isDark,
            background: mix(\.background),
            secondaryBackground: mix(\.secondaryBackground),
            primary: mix(\.primary),
            secondary: mix(\.secondary),
            separator: mix(\.separator),
            threadLine: mix(\.threadLine),
            highlight: mix(\.highlight),
            marker: mix(\.marker),
            redMarker: mix(\.redMarker),
            blueMarker: mix(\.blueMarker),
            yellowIcon: mix(\.yellowIcon),
            redIcon: mix(\.redIcon),
            blueIcon: mix(\.blueIcon)
        )
    }

    /// A palette made from its background and text colours. The other colours are tints of
    /// the background.
    static func derived(background: UInt32, primary: UInt32, secondary: UInt32, isDark: Bool) -> ThemePalette {
        let mix = PaletteHex.mix
        if isDark {
            return ThemePalette(
                isDark: true,
                background: background,
                secondaryBackground: mix(background, 0xFFFFFF, 0.08),
                primary: primary,
                secondary: secondary,
                separator: mix(background, 0xFFFFFF, 0.16),
                threadLine: mix(background, 0xFFFFFF, 0.18),
                highlight: mix(background, 0xFF8A3D, 0.25),
                marker: mix(background, 0xFFD400, 0.28),
                redMarker: mix(background, 0xF4212E, 0.3),
                blueMarker: mix(background, 0x1D9BF0, 0.3),
                yellowIcon: PaletteHex.darkYellowIcon,
                redIcon: PaletteHex.darkRedIcon,
                blueIcon: PaletteHex.darkBlueIcon
            )
        }
        return ThemePalette(
            isDark: false,
            background: background,
            secondaryBackground: mix(background, 0x000000, 0.03),
            primary: primary,
            secondary: secondary,
            separator: mix(background, 0x000000, 0.07),
            threadLine: mix(background, 0x000000, 0.15),
            highlight: mix(background, 0xFFB070, 0.3),
            marker: mix(background, 0xFFE15C, 0.5),
            redMarker: mix(background, 0xFF9A9A, 0.4),
            blueMarker: mix(background, 0x8CC4FF, 0.4),
            yellowIcon: PaletteHex.lightYellowIcon,
            redIcon: PaletteHex.lightRedIcon,
            blueIcon: PaletteHex.lightBlueIcon
        )
    }

    /// Changes only the colours that miss their contrast target, and only as much as needed:
    /// primary text 7:1 on the backgrounds and on every marker, secondary text and accents
    /// 4.5:1, icons 3:1. Text moves away from the background; markers move towards it.
    func readable() -> ThemePalette {
        var palette = self
        let away: UInt32 = isDark ? 0xFFFFFF : 0x000000
        let toward: UInt32 = isDark ? 0x000000 : 0xFFFFFF
        let backgrounds = [background, secondaryBackground]
        func fix(_ color: UInt32, on others: [UInt32], _ target: Double, moving end: UInt32) -> UInt32 {
            PaletteHex.readable(color, on: others, target: target, toward: end)
        }
        palette.primary = fix(primary, on: backgrounds, 7, moving: away)
        palette.highlight = fix(highlight, on: [palette.primary], 7, moving: toward)
        palette.marker = fix(marker, on: [palette.primary], 7, moving: toward)
        palette.redMarker = fix(redMarker, on: [palette.primary], 7, moving: toward)
        palette.blueMarker = fix(blueMarker, on: [palette.primary], 7, moving: toward)
        palette.secondary = fix(secondary, on: backgrounds, 4.5, moving: away)
        palette.yellowIcon = fix(yellowIcon, on: backgrounds, 3, moving: away)
        palette.redIcon = fix(redIcon, on: backgrounds, 3, moving: away)
        palette.blueIcon = fix(blueIcon, on: backgrounds, 3, moving: away)
        palette.accents = AccentChoice.allCases.map { choice in
            fix(isDark ? choice.hex.dark : choice.hex.light, on: backgrounds, 4.5, moving: away)
        }
        return palette
    }

    /// Night at its default brightness: X's "Lights out".
    static let night = ThemePalette(
        isDark: true,
        background: PaletteHex.darkBackground,
        secondaryBackground: PaletteHex.darkSecondaryBackground,
        primary: PaletteHex.darkPrimary,
        secondary: PaletteHex.darkSecondary,
        separator: 0x2F3336,
        threadLine: 0x333639,
        highlight: PaletteHex.darkHighlight,
        marker: PaletteHex.darkMarker,
        redMarker: PaletteHex.darkRedMarker,
        blueMarker: PaletteHex.darkBlueMarker,
        yellowIcon: PaletteHex.darkYellowIcon,
        redIcon: PaletteHex.darkRedIcon,
        blueIcon: PaletteHex.darkBlueIcon
    )

    /// Light at its default brightness: X's white.
    static let light = ThemePalette(
        isDark: false,
        background: PaletteHex.lightBackground,
        secondaryBackground: PaletteHex.lightSecondaryBackground,
        primary: PaletteHex.lightPrimary,
        secondary: PaletteHex.lightSecondary,
        separator: 0xEFF3F4,
        threadLine: 0xCFD9DE,
        highlight: PaletteHex.lightHighlight,
        marker: PaletteHex.lightMarker,
        redMarker: PaletteHex.lightRedMarker,
        blueMarker: PaletteHex.lightBlueMarker,
        yellowIcon: PaletteHex.lightYellowIcon,
        redIcon: PaletteHex.lightRedIcon,
        blueIcon: PaletteHex.lightBlueIcon
    )

    /// Sepia at its default brightness.
    static let sepia = ThemePalette(
        isDark: false,
        background: PaletteHex.sepiaBackground,
        secondaryBackground: PaletteHex.sepiaSecondaryBackground,
        primary: PaletteHex.sepiaPrimary,
        secondary: PaletteHex.sepiaSecondary,
        separator: 0xE3D5BC,
        threadLine: 0xD9C9AC,
        highlight: PaletteHex.sepiaHighlight,
        marker: PaletteHex.sepiaMarker,
        redMarker: PaletteHex.sepiaRedMarker,
        blueMarker: PaletteHex.sepiaBlueMarker,
        yellowIcon: PaletteHex.sepiaYellowIcon,
        redIcon: PaletteHex.sepiaRedIcon,
        blueIcon: PaletteHex.sepiaBlueIcon
    )
}

extension AppTheme {
    /// True for themes with light text on a dark background; nil for System.
    var isDark: Bool? {
        switch self {
        case .night, .darkSepia, .dusk: return true
        case .light, .sepia, .sage: return false
        case .system: return nil
        }
    }

    /// System follows the device and has no brightness of its own.
    var hasBrightness: Bool { self != .system }

    /// The brightness a theme starts at: Night is pure black, Light is white, and Sepia is
    /// the sepia of earlier versions.
    var defaultBrightness: Double {
        switch self {
        case .night: return 0
        case .light, .system: return 1
        case .sepia: return 0.8
        case .darkSepia, .dusk: return 0.4
        case .sage: return 0.75
        }
    }

    /// The theme's palettes at fixed brightness points (0 is darkest, 1 is lightest).
    /// Between two points the colours are mixed.
    private var anchors: [(brightness: Double, palette: ThemePalette)] {
        let derived = ThemePalette.derived
        switch self {
        case .night, .system:
            return [(0, ThemePalette.night), (1, derived(0x26292D, 0xE7E9EA, 0x9AA1A7, true))]
        case .light:
            return [(0, derived(0xC9CED3, 0x0F1419, 0x3E4A55, false)), (1, ThemePalette.light)]
        case .sepia:
            return [
                (0, derived(0xC9AB80, 0x22180E, 0x47382A, false)),
                (0.8, ThemePalette.sepia),
                (1, derived(0xFCF8F0, 0x3D2E1F, 0x6B5A45, false)),
            ]
        case .darkSepia:
            return [(0, derived(0x120D08, 0xE6D6BE, 0xA8957A, true)), (1, derived(0x433426, 0xF2E6D3, 0xC9B79C, true))]
        case .sage:
            return [(0, derived(0xAEBFA0, 0x16201A, 0x34443A, false)), (1, derived(0xF3F7EF, 0x1D2A1F, 0x4B5B4B, false))]
        case .dusk:
            return [(0, derived(0x0B1019, 0xDFE6F0, 0x95A3B6, true)), (1, derived(0x2F3B52, 0xEEF2F8, 0xBAC6D6, true))]
        }
    }

    /// The theme's colours at `brightness` (0...1), with every text colour readable.
    /// System uses Light at 1 and Night at 0.
    func palette(brightness: Double) -> ThemePalette {
        let value = brightness.isFinite ? min(max(brightness, 0), 1) : defaultBrightness
        let points = anchors
        var palette = points[0].palette
        for (lower, upper) in zip(points, points.dropFirst()) where value >= lower.brightness {
            let span = upper.brightness - lower.brightness
            palette = ThemePalette.mixed(lower.palette, upper.palette, span > 0 ? min(1, (value - lower.brightness) / span) : 1)
        }
        return palette.readable()
    }
}
