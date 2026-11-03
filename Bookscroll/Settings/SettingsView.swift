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
                    Picker("Density", selection: $settings.density) {
                        ForEach(Density.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    Picker("Post font", selection: $settings.postTypeface) {
                        ForEach(Typeface.allCases) { face in
                            Text(face.title).tag(face)
                        }
                    }
                    Picker("Post style", selection: $styleRaw) {
                        ForEach(PostStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    Picker("Maximum words per post", selection: $settings.wordLimit) {
                        ForEach(WordLimit.choices, id: \.self) { limit in
                            Text(limit.title).tag(limit)
                        }
                    }
                    .accessibilityIdentifier("settings.wordLimit")
                    Toggle("Focus mode", isOn: $settings.focusMode)
                        .accessibilityIdentifier("settings.focusMode")
                    Toggle("Double-tap to like", isOn: $settings.doubleTapToLike)
                } header: {
                    Text("Posts")
                } footer: {
                    Text("A longer paragraph continues in the next post (1/2, 2/2), cut between sentences. Auto fits 95% of each book's paragraphs in one post. Focus mode shows only the text of each post. Text size follows the system setting (Settings \u{203A} Display & Brightness \u{203A} Text Size).")
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)

                Section("Reader") {
                    Picker("Reader font", selection: $settings.readerTypeface) {
                        ForEach(Typeface.allCases) { face in
                            Text(face == .sans ? "Sans" : face.title).tag(face)
                        }
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
