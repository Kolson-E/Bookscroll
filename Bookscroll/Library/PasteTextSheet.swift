import SwiftUI

/// Paste Text: makes a book from text, such as an article or notes. Blank lines separate
/// paragraphs; a short line such as "Chapter 2" starts a chapter.
@MainActor
struct PasteTextSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var text = ""
    @ScaledMetric(relativeTo: .body) private var editorHeight: CGFloat = 220
    private enum Field { case title, author, text }
    @FocusState private var focus: Field?

    private var hasText: Bool { TextUtils.hasLetterOrDigit(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityIdentifier("paste.title")
                        .focused($focus, equals: .title)
                    TextField("Author (optional)", text: $author)
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityIdentifier("paste.author")
                        .focused($focus, equals: .author)
                } header: {
                    SectionHeader("Book")
                }
                .listRowBackground(Theme.secondaryBackground)

                Section {
                    TextEditor(text: $text)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: editorHeight)
                        .accessibilityLabel("Text")
                        .accessibilityIdentifier("paste.text")
                        .focused($focus, equals: .text)
                    PasteButton(payloadType: String.self) { strings in
                        let pasted = strings.joined(separator: "\n\n")
                        Task { @MainActor in
                            text = text.isEmpty ? pasted : text + "\n\n" + pasted
                        }
                    }
                    .labelStyle(.titleAndIcon)
                } header: {
                    SectionHeader("Text")
                } footer: {
                    Text(footer)
                        .foregroundStyle(Theme.secondaryText)
                }
                .listRowBackground(Theme.secondaryBackground)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Paste Text")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Hides the keyboard, so the word count and the Paste button show again.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("paste.keyboardDone")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        app.importer.enqueuePasted(text: text, title: title, author: author)
                        app.selectedTab = .library
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasText)
                    .accessibilityIdentifier("paste.add")
                }
            }
        }
        .tint(Theme.accent)
    }

    private var footer: String {
        let words = TextUtils.wordCount(text)
        let count = words == 1 ? "1 word." : "\(words.formatted()) words."
        return "\(count) Blank lines separate paragraphs. A short line such as \u{201C}Chapter 2\u{201D} starts a chapter."
    }
}
