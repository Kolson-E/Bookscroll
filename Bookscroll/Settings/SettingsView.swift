import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage("postStyle") private var styleRaw = PostStyle.paragraph.rawValue

    var body: some View {
        @Bindable var settings = AppSettings.shared
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                    AccentPicker(selection: $settings.accent)
                    ChoiceRow(title: "Density", selection: $settings.density, choices: Density.allCases) { $0.title }
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    ChoiceRow(title: "Post font", selection: $settings.postTypeface, choices: Typeface.allCases) { $0.title }
                    ChoiceRow(title: "Post style", selection: $styleRaw, choices: PostStyle.allCases.map(\.rawValue)) {
                        PostStyle(rawValue: $0)?.title ?? $0
                    }
                    ChoiceRow(
                        title: "Maximum words per post",
                        selection: $settings.wordLimit,
                        choices: WordLimit.choices,
                        footer: "Auto picks, for each book, the smallest limit that fits 95% of its paragraphs in one post (at least 40 words). A longer paragraph continues in the next post, cut between sentences."
                    ) { $0.title }
                    .accessibilityIdentifier("settings.wordLimit")
                    Toggle("Focus mode", isOn: $settings.focusMode)
                        .accessibilityIdentifier("settings.focusMode")
                    Toggle("Double-tap to like", isOn: $settings.doubleTapToLike)
                } header: {
                    Text("Posts")
                } footer: {
                    Text("A longer paragraph continues in the next post (1/2, 2/2). Focus mode shows only the text of each post. Text size follows the system setting (Settings \u{203A} Display & Brightness \u{203A} Text Size).")
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section("Reader") {
                    ChoiceRow(title: "Reader font", selection: $settings.readerTypeface, choices: Typeface.allCases) {
                        $0 == .sans ? "Sans" : $0.title
                    }
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    LabeledContent("Version", value: Self.version)
                } header: {
                    Text("About")
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

/// A setting with a few choices: the title and the current choice in the row, the choices on
/// the next screen. Used in place of a menu picker, whose value label can be cut off at large
/// text sizes and does not take the theme's colours.
@MainActor
struct ChoiceRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    var footer: String?
    let label: (Value) -> String

    init(title: String, selection: Binding<Value>, choices: [Value], footer: String? = nil, label: @escaping (Value) -> String) {
        self.title = title
        _selection = selection
        self.choices = choices
        self.footer = footer
        self.label = label
    }

    var body: some View {
        NavigationLink {
            ChoiceList(title: title, selection: $selection, choices: choices, footer: footer, label: label)
        } label: {
            // Title and value share the line when they fit; at large text sizes they stack.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(title).foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                    Text(label(selection)).foregroundStyle(Theme.secondaryText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Theme.primaryText)
                    Text(label(selection)).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        .accessibilityAddTraits(.isButton)
    }
}

@MainActor
private struct ChoiceList<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let choices: [Value]
    let footer: String?
    let label: (Value) -> String

    var body: some View {
        List {
            Section {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        selection = choice
                    } label: {
                        HStack {
                            Text(label(choice)).foregroundStyle(Theme.primaryText)
                            Spacer(minLength: 8)
                            if choice == selection {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(choice == selection ? [.isSelected] : [])
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
