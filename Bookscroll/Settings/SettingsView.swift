import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue
    @State private var openChoice: SettingChoice?

    /// The settings that open a list of choices.
    enum SettingChoice: String, Identifiable, Hashable {
        case density
        case postFont
        case postStyle
        case wordLimit
        case readerFont

        var id: Self { self }
    }

    var body: some View {
        @Bindable var settings = AppSettings.shared
        NavigationStack {
            Form {
                Section {
                    Text("Theme").foregroundStyle(Theme.primaryText)
                    ForEach(AppTheme.allCases) { theme in
                        CheckRow(title: theme.title, isSelected: settings.theme == theme) {
                            settings.theme = theme
                        }
                    }
                    AccentPicker(selection: $settings.accent)
                    ChoiceRow(title: "Density", value: settings.density.title) { openChoice = .density }
                } header: {
                    SectionHeader("Appearance")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    ChoiceRow(title: "Post font", value: settings.postTypeface.title) { openChoice = .postFont }
                    ChoiceRow(title: "Post style", value: PostStyle(rawValue: styleRaw)?.title ?? styleRaw) { openChoice = .postStyle }
                    ChoiceRow(title: "Maximum words per post", value: settings.wordLimit.title) { openChoice = .wordLimit }
                        .accessibilityIdentifier("settings.wordLimit")
                    Toggle("Focus mode", isOn: $settings.focusMode)
                        .accessibilityIdentifier("settings.focusMode")
                    Toggle("Double-tap to like", isOn: $settings.doubleTapToLike)
                } header: {
                    SectionHeader("Posts")
                } footer: {
                    Text("A longer paragraph continues in the next post (1/2, 2/2), cut between sentences. Auto picks, for each book, the smallest limit that fits 95% of its paragraphs in one post (at least 40 words). Focus mode shows only the text of each post. Text size follows the system setting (Settings \u{203A} Display & Brightness \u{203A} Text Size).")
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    ChoiceRow(title: "Reader font", value: Self.readerFontTitle(settings.readerTypeface)) { openChoice = .readerFont }
                } header: {
                    SectionHeader("Reader")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    HStack {
                        Text("Version").foregroundStyle(Theme.primaryText)
                        Spacer(minLength: 8)
                        Text(Self.version).foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                } header: {
                    SectionHeader("About")
                } footer: {
                    Text("Bookscroll works fully offline. It has no account, no analytics and makes no network calls.")
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .navigationDestination(item: $openChoice) { choice in
                choiceList(choice)
            }
        }
    }

    @ViewBuilder
    private func choiceList(_ choice: SettingChoice) -> some View {
        @Bindable var settings = AppSettings.shared
        switch choice {
        case .density:
            ChoiceList(title: "Density", selection: $settings.density, choices: Density.allCases) { $0.title }
        case .postFont:
            ChoiceList(title: "Post font", selection: $settings.postTypeface, choices: Typeface.allCases) { $0.title }
        case .postStyle:
            ChoiceList(title: "Post style", selection: $styleRaw, choices: PostStyle.allCases.map(\.rawValue)) {
                PostStyle(rawValue: $0)?.title ?? $0
            }
        case .wordLimit:
            ChoiceList(
                title: "Maximum words per post",
                selection: $settings.wordLimit,
                choices: WordLimit.choices,
                footer: "Auto picks, for each book, the smallest limit that fits 95% of its paragraphs in one post."
            ) { $0.title }
        case .readerFont:
            ChoiceList(title: "Reader font", selection: $settings.readerTypeface, choices: Typeface.allCases) {
                Self.readerFontTitle($0)
            }
        }
    }

    private static func readerFontTitle(_ typeface: Typeface) -> String {
        typeface == .sans ? "Sans" : typeface.title
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// X's six accent swatches. Each swatch is a button with its colour name for VoiceOver.
@MainActor
private struct AccentPicker: View {
    @Binding var selection: AccentChoice
    @ScaledMetric(relativeTo: .body) private var swatch: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accent colour")
            HStack(spacing: 0) {
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        selection = choice
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: min(swatch, 44), height: min(swatch, 44))
                            .overlay {
                                if choice == selection {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(Theme.background)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(choice == selection ? [.isSelected] : [])
                    .accessibilityIdentifier("accent.\(choice.rawValue)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accent colour")
    }
}

/// A section header in the theme's secondary text colour (the system grey is too light on
/// the sepia rows).
@MainActor
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .foregroundStyle(Theme.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A row that is one choice of a list, with a checkmark when selected.
@MainActor
private struct CheckRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A setting with a few choices: the title and the current choice in the row. A tap opens
/// the list of choices. The row and its chevron are drawn here, not by the system menu or
/// navigation link, so they follow Dynamic Type, wrap at large text sizes and use the theme's
/// colours.
@MainActor
struct ChoiceRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                // Title and value share the line when they fit; at large text sizes they stack.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Text(title).foregroundStyle(Theme.primaryText)
                        Spacer(minLength: 8)
                        Text(value).foregroundStyle(Theme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).foregroundStyle(Theme.primaryText)
                        Text(value).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .imageScale(.small)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAddTraits(.isButton)
    }
}

/// The choices of one setting, with a checkmark on the current one.
@MainActor
struct ChoiceList<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    var footer: String?
    let label: (Value) -> String

    var body: some View {
        List {
            Section {
                ForEach(choices, id: \.self) { choice in
                    CheckRow(title: label(choice), isSelected: choice == selection) {
                        selection = choice
                    }
                    .frame(minHeight: 44)
                }
            } footer: {
                if let footer {
                    Text(footer).foregroundStyle(Theme.secondaryText)
                }
            }
            .listRowBackground(Theme.secondaryBackground)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .themedNavigationBar()
    }
}
