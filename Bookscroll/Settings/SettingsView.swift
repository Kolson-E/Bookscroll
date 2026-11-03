import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue

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
                    ChoiceRow(title: "Density", selection: $settings.density, choices: Density.allCases) { $0.title }
                } header: {
                    SectionHeader("Appearance")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    ChoiceRow(title: "Post font", selection: $settings.postTypeface, choices: Typeface.allCases) { $0.title }
                    ChoiceRow(title: "Post style", selection: $styleRaw, choices: PostStyle.allCases.map(\.rawValue)) {
                        PostStyle(rawValue: $0)?.title ?? $0
                    }
                    ChoiceRow(title: "Maximum words per post", selection: $settings.wordLimit, choices: WordLimit.choices) { $0.title }
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
                    ChoiceRow(title: "Reader font", selection: $settings.readerTypeface, choices: Typeface.allCases) {
                        $0 == .sans ? "Sans" : $0.title
                    }
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
        }
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
private struct SectionHeader: View {
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

/// A setting with a few choices: the title and the current choice in the row, the choices in
/// a menu. The label is drawn here, not by the system picker, so it wraps at large text sizes
/// and uses the theme's colours.
@MainActor
struct ChoiceRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    let label: (Value) -> String

    init(title: String, selection: Binding<Value>, choices: [Value], label: @escaping (Value) -> String) {
        self.title = title
        _selection = selection
        self.choices = choices
        self.label = label
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(choices, id: \.self) { choice in
                    Text(label(choice)).tag(choice)
                }
            }
        } label: {
            // Title and value share the line when they fit; at large text sizes they stack.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(title).foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                    value
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.primaryText)
                    value
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }

    private var value: some View {
        HStack(spacing: 4) {
            Text(label(selection))
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.secondaryText)
    }
}
