import Observation
import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    /// Pure black, like X's "Lights out". The default.
    case night
    case light
    case sepia
    /// Light text on dark brown paper.
    case darkSepia
    /// Dark text on pale green-grey.
    case sage
    /// Light text on dark blue-slate.
    case dusk
    /// Follows the system light or dark setting.
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: return String(localized: "Night")
        case .light: return String(localized: "Light")
        case .sepia: return String(localized: "Sepia")
        case .darkSepia: return String(localized: "Dark sepia")
        case .sage: return String(localized: "Sage")
        case .dusk: return String(localized: "Dusk")
        case .system: return String(localized: "System")
        }
    }

    var colorScheme: ColorScheme? {
        isDark.map { $0 ? .dark : .light }
    }
}

/// X's six accent colours. Each has a bright shade for dark backgrounds and a deep shade for
/// light backgrounds. A theme made lighter or darker with its brightness slider moves the
/// shade further only as needed to keep 4.5:1 (`ThemePalette.accent(_:)`), so the accent can
/// always colour text.
enum AccentChoice: String, CaseIterable, Identifiable {
    case blue
    case yellow
    case pink
    case purple
    case orange
    case green

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// sRGB hex for dark backgrounds and for light backgrounds.
    var hex: (dark: UInt32, light: UInt32) {
        switch self {
        case .blue: return (0x1D9BF0, 0x0B6BB0)
        case .yellow: return (0xFFD400, 0x7A5F00)
        case .pink: return (0xF91880, 0xC2135F)
        case .purple: return (0x9076FF, 0x5B3BE0)
        case .orange: return (0xFF7A00, 0xA84800)
        case .green: return (0x00BA7C, 0x00764F)
        }
    }

    var color: Color {
        let (dark, light) = hex
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

enum Density: String, CaseIterable, Identifiable {
    case comfortable
    case compact

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Reading fonts. Apple Books offers most of these; all ship with iOS. A stored font that
/// is no longer offered (Rounded, Monospaced) falls back to the default.
enum Typeface: String, CaseIterable, Identifiable {
    /// The system sans-serif (SF Pro), sized and spaced like X posts.
    case sans
    /// The system serif, New York.
    case serif
    case georgia
    case charter
    case iowan
    case palatino
    case athelas
    case baskerville
    case hoefler
    /// A humanist sans-serif made for reading.
    case seravek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sans: return String(localized: "Sans (X style)")
        case .serif: return "New York"
        case .georgia: return "Georgia"
        case .charter: return "Charter"
        case .iowan: return "Iowan Old Style"
        case .palatino: return "Palatino"
        case .athelas: return "Athelas"
        case .baskerville: return "Baskerville"
        case .hoefler: return "Hoefler Text"
        case .seravek: return "Seravek"
        }
    }

    /// PostScript names of the regular and bold faces; nil for the two system fonts.
    var faceNames: (regular: String, bold: String)? {
        switch self {
        case .sans, .serif: return nil
        case .georgia: return ("Georgia", "Georgia-Bold")
        case .charter: return ("Charter-Roman", "Charter-Bold")
        case .iowan: return ("IowanOldStyle-Roman", "IowanOldStyle-Bold")
        case .palatino: return ("Palatino-Roman", "Palatino-Bold")
        case .athelas: return ("Athelas-Regular", "Athelas-Bold")
        case .baskerville: return ("Baskerville", "Baskerville-Bold")
        case .hoefler: return ("HoeflerText-Regular", "HoeflerText-Black")
        case .seravek: return ("Seravek", "Seravek-Bold")
        }
    }

    /// The system design (for the system fonts).
    var design: Font.Design { self == .serif ? .serif : .default }

    /// The same design for UIKit text; nil for the default system font.
    var systemDesign: UIFontDescriptor.SystemDesign? { self == .serif ? .serif : nil }

    /// The font at a fixed size (post text sets its own size and scaling).
    func font(size: CGFloat, bold: Bool = false) -> Font {
        if let faceNames { return .custom(bold ? faceNames.bold : faceNames.regular, fixedSize: size) }
        return .system(size: size, weight: bold ? .bold : .regular, design: design)
    }

    /// The font at a text style's size, following Dynamic Type.
    func font(_ style: Font.TextStyle, bold: Bool = false) -> Font {
        if let faceNames {
            return .custom(bold ? faceNames.bold : faceNames.regular, size: Self.pointSize(style), relativeTo: style)
        }
        let font = Font.system(style, design: design)
        return bold ? font.weight(.semibold) : font
    }

    /// The UIKit font at a fixed size. The system font when the face is missing.
    func uiFont(size: CGFloat, bold: Bool = false) -> UIFont {
        if let faceNames, let font = UIFont(name: bold ? faceNames.bold : faceNames.regular, size: size) { return font }
        let system = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard let systemDesign, let descriptor = system.fontDescriptor.withDesign(systemDesign) else { return system }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// The UIKit font at a text style's size, following Dynamic Type.
    func uiFont(textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: textStyle)
        if let faceNames {
            let size = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize
            guard let font = UIFont(name: faceNames.regular, size: size) else { return base }
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        }
        guard let systemDesign, let descriptor = base.fontDescriptor.withDesign(systemDesign) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// Point size of a text style at the default text size (Large).
    static func pointSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }
}

/// The size of post text, in points, in steps of half a point.
enum PostTextSize {
    /// Matches the X iPhone app: measured on an iPhone screenshot, X's post glyphs are as tall
    /// as SF Pro at 16.5 pt (x.com on the web uses 15 px, which is smaller).
    static let standard: Double = 16.5
    static let range: ClosedRange<Double> = 10...40
    static let step: Double = 0.5

    /// Rounds to the nearest half point and keeps the size in `range`.
    static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return standard }
        return min(max((value / step).rounded() * step, range.lowerBound), range.upperBound)
    }

    /// Reads a typed size: "17", "17.5" or "17,5". Nil when it is not a number.
    static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite else { return nil }
        return clamped(value)
    }

    /// "17" or "17.5", with the device's decimal separator.
    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Line height as in the X iPhone app: 1.25 times the text size (20.6 pt lines at 16.5 pt).
    static let lineHeightRatio: CGFloat = 1.25
    static func lineHeight(for size: CGFloat) -> CGFloat { size * lineHeightRatio }
}

/// App-wide settings, stored in UserDefaults. Views read them through `AppSettings.shared`;
/// Observation re-renders a view when a setting it read changes.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Key {
        static let theme = "appTheme"
        /// Brightness of each theme (0 darkest, 1 lightest), keyed by theme.
        static let themeBrightness = "themeBrightness"
        static let accent = "accentChoice"
        static let density = "density"
        static let postTypeface = "postTypeface"
        static let readerTypeface = "readerTypeface"
        static let postTextSize = "postTextSize"
        static let focusMode = "focusMode"
        /// Stored under its old name (double tap used to like).
        static let doubleTapToBookmark = "doubleTapToLike"
        static let wordLimit = "wordLimit"
        static let scrollBackInOneBook = "scrollBackInOneBook"
        static let liveActivity = "liveActivity"
        static let all = [theme, themeBrightness, accent, density, postTypeface, readerTypeface, postTextSize, focusMode, doubleTapToBookmark, wordLimit, liveActivity, scrollBackInOneBook]
    }

    @ObservationIgnored private let defaults: UserDefaults

    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// Brightness per theme (raw value to 0...1). Read it through `brightness(for:)`.
    private(set) var themeBrightness: [String: Double] { didSet { defaults.set(themeBrightness, forKey: Key.themeBrightness) } }
    var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: Key.accent) } }
    var density: Density { didSet { defaults.set(density.rawValue, forKey: Key.density) } }
    var postTypeface: Typeface { didSet { defaults.set(postTypeface.rawValue, forKey: Key.postTypeface) } }
    var readerTypeface: Typeface { didSet { defaults.set(readerTypeface.rawValue, forKey: Key.readerTypeface) } }
    /// Post text size in points (half-point steps). Set it through `PostTextSize.clamped`.
    var postTextSize: Double { didSet { defaults.set(postTextSize, forKey: Key.postTextSize) } }
    /// Posts show only their text: no title line, progress line or actions.
    var focusMode: Bool { didSet { defaults.set(focusMode, forKey: Key.focusMode) } }
    var doubleTapToBookmark: Bool { didSet { defaults.set(doubleTapToBookmark, forKey: Key.doubleTapToBookmark) } }
    /// Maximum words per post. Auto (the default) fits 95% of each book's paragraphs.
    var wordLimit: WordLimit { didSet { defaults.set(wordLimit.storage, forKey: Key.wordLimit) } }
    /// Shows the book being read on the Lock Screen and in the Dynamic Island.
    var liveActivity: Bool { didSet { defaults.set(liveActivity, forKey: Key.liveActivity) } }
    /// One book mode: scrolling up goes back through the book. Your place still only moves forward.
    var scrollBackInOneBook: Bool { didSet { defaults.set(scrollBackInOneBook, forKey: Key.scrollBackInOneBook) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme).flatMap(AppTheme.init) ?? .night
        themeBrightness = (defaults.dictionary(forKey: Key.themeBrightness) ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .blue
        density = defaults.string(forKey: Key.density).flatMap(Density.init) ?? .comfortable
        postTypeface = defaults.string(forKey: Key.postTypeface).flatMap(Typeface.init) ?? .sans
        readerTypeface = defaults.string(forKey: Key.readerTypeface).flatMap(Typeface.init) ?? .serif
        postTextSize = defaults.object(forKey: Key.postTextSize) == nil
            ? PostTextSize.standard
            : PostTextSize.clamped(defaults.double(forKey: Key.postTextSize))
        focusMode = Self.bool(defaults, Key.focusMode, default: false)
        doubleTapToBookmark = Self.bool(defaults, Key.doubleTapToBookmark, default: true)
        wordLimit = defaults.object(forKey: Key.wordLimit) == nil ? .auto : WordLimit(storage: defaults.integer(forKey: Key.wordLimit))
        liveActivity = Self.bool(defaults, Key.liveActivity, default: true)
        scrollBackInOneBook = Self.bool(defaults, Key.scrollBackInOneBook, default: false)
    }
}

extension AppSettings {
    /// The theme's brightness (0 darkest, 1 lightest); its default when never set.
    func brightness(for theme: AppTheme) -> Double {
        guard let value = themeBrightness[theme.rawValue], value.isFinite else { return theme.defaultBrightness }
        return min(max(value, 0), 1)
    }

    func setBrightness(_ value: Double, for theme: AppTheme) {
        guard theme.hasBrightness, value.isFinite else { return }
        themeBrightness[theme.rawValue] = min(max(value, 0), 1)
    }

    /// Back to the theme's default brightness.
    func resetBrightness(for theme: AppTheme) {
        themeBrightness[theme.rawValue] = nil
    }

    /// `bool(forKey:)` also reads "YES"/"NO" given as launch arguments.
    private static func bool(_ defaults: UserDefaults, _ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
