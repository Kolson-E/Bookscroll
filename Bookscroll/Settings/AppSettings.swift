import Observation
import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    /// Pure black, like X's "Lights out". The default.
    case night
    case light
    case sepia
    /// Follows the system light or dark setting.
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: return "Night"
        case .light: return "Light"
        case .sepia: return "Sepia"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .night: return .dark
        case .light, .sepia: return .light
        case .system: return nil
        }
    }
}

/// X's six accent colours. Each has a bright shade for dark backgrounds and a deep shade for
/// light and sepia backgrounds; both reach 4.5:1 against their background, so the accent can
/// colour text.
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

enum Typeface: String, CaseIterable, Identifiable {
    /// The system sans-serif (SF Pro), sized and spaced like X posts.
    case sans
    case serif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sans: return "Sans (X style)"
        case .serif: return "Serif"
        }
    }

    var design: Font.Design {
        self == .serif ? .serif : .default
    }
}

/// App-wide settings, stored in UserDefaults. Views read them through `AppSettings.shared`;
/// Observation re-renders a view when a setting it read changes.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum Key {
        static let theme = "appTheme"
        static let accent = "accentChoice"
        static let density = "density"
        static let postTypeface = "postTypeface"
        static let readerTypeface = "readerTypeface"
        static let focusMode = "focusMode"
        static let doubleTapToLike = "doubleTapToLike"
        static let wordLimit = "wordLimit"
        static let liveActivity = "liveActivity"
        static let all = [theme, accent, density, postTypeface, readerTypeface, focusMode, doubleTapToLike, wordLimit, liveActivity]
    }

    @ObservationIgnored private let defaults: UserDefaults

    var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: Key.accent) } }
    var density: Density { didSet { defaults.set(density.rawValue, forKey: Key.density) } }
    var postTypeface: Typeface { didSet { defaults.set(postTypeface.rawValue, forKey: Key.postTypeface) } }
    var readerTypeface: Typeface { didSet { defaults.set(readerTypeface.rawValue, forKey: Key.readerTypeface) } }
    /// Posts show only their text: no title line, progress line or actions.
    var focusMode: Bool { didSet { defaults.set(focusMode, forKey: Key.focusMode) } }
    var doubleTapToLike: Bool { didSet { defaults.set(doubleTapToLike, forKey: Key.doubleTapToLike) } }
    /// Maximum words per post. Auto (the default) fits 95% of each book's paragraphs.
    var wordLimit: WordLimit { didSet { defaults.set(wordLimit.storage, forKey: Key.wordLimit) } }
    /// Shows the book being read on the Lock Screen and in the Dynamic Island.
    var liveActivity: Bool { didSet { defaults.set(liveActivity, forKey: Key.liveActivity) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        theme = defaults.string(forKey: Key.theme).flatMap(AppTheme.init) ?? .night
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init) ?? .blue
        density = defaults.string(forKey: Key.density).flatMap(Density.init) ?? .comfortable
        postTypeface = defaults.string(forKey: Key.postTypeface).flatMap(Typeface.init) ?? .sans
        readerTypeface = defaults.string(forKey: Key.readerTypeface).flatMap(Typeface.init) ?? .serif
        focusMode = Self.bool(defaults, Key.focusMode, default: false)
        doubleTapToLike = Self.bool(defaults, Key.doubleTapToLike, default: true)
        wordLimit = defaults.object(forKey: Key.wordLimit) == nil ? .auto : WordLimit(storage: defaults.integer(forKey: Key.wordLimit))
        liveActivity = Self.bool(defaults, Key.liveActivity, default: true)
    }
}

extension AppSettings {
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
