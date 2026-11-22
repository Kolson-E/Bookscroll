import SwiftUI

struct JumpRequest: Identifiable {
    let id = UUID()
    let bookID: UUID
}

/// "Jump to": the start of the book, a percent, or a chapter. Chapters you have reached are
/// ticked; the chapter you are in is marked. Choosing a place opens the book in One book mode
/// from there.
@MainActor
struct JumpSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let bookID: UUID
    @State private var percent: Double = 0
    @State private var loaded = false

    private var book: FeedBook? { app.store.feedBook(id: bookID) }
    private var chapters: [ChapterEntry] { app.store.chapters(bookID: bookID) }

    var body: some View {
        NavigationStack {
            Group {
                if let book {
                    content(book)
                } else {
                    ContentUnavailableView("Book not found", systemImage: "book.closed")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .onAppear {
            guard !loaded, let book else { return }
            loaded = true
            percent = Double(TextUtils.percent(book.positionOffset, of: book.totalCharacters))
        }
    }

    private func content(_ book: FeedBook) -> some View {
        let current = currentChapterIndex(book)
        return List {
            Section {
                Button {
                    go(book, offset: 0)
                } label: {
                    Label("Start of book", systemImage: "arrow.up.to.line")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $percent, in: 0...100, step: 1) {
                        Text("Percent")
                    }
                    .accessibilityValue("\(Int(percent)) percent")
                    Button {
                        go(book, offset: offset(book, percent: percent))
                    } label: {
                        Label("Go to \(Int(percent))%", systemImage: "arrow.right.circle")
                    }
                    .accessibilityIdentifier("jump.percent")
                }
                .padding(.vertical, 4)
            } header: {
                Text("\(book.title) \u{00B7} now at \(TextUtils.percent(book.positionOffset, of: book.totalCharacters))%")
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)

            Section {
                if chapters.isEmpty {
                    Text("This book has no chapter labels.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { n, chapter in
                        Button {
                            go(book, offset: chapter.charStart)
                        } label: {
                            ChapterRow(
                                chapter: chapter,
                                percent: TextUtils.percent(chapter.charStart, of: book.totalCharacters),
                                isCurrent: n == current,
                                isReached: chapter.charStart <= book.positionOffset
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Chapters").foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    /// The last chapter that starts at or before the reading position.
    private func currentChapterIndex(_ book: FeedBook) -> Int? {
        chapters.lastIndex { $0.charStart <= book.positionOffset }
    }

    private func offset(_ book: FeedBook, percent: Double) -> Int {
        min(max(0, Int(Double(book.totalCharacters) * percent / 100)), max(0, book.totalCharacters - 1))
    }

    private func go(_ book: FeedBook, offset: Int) {
        dismiss()
        app.jump(bookID: book.id, offset: offset)
    }
}

@MainActor
private struct ChapterRow: View {
    let chapter: ChapterEntry
    let percent: Int
    let isCurrent: Bool
    let isReached: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCurrent ? "location.fill" : (isReached ? "checkmark.circle.fill" : "circle"))
                .foregroundStyle(isCurrent || isReached ? Theme.accent : Theme.secondaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isCurrent ? "You are here \u{00B7} \(percent)%" : "\(percent)%")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chapter.title), \(percent) percent\(isCurrent ? ", you are here" : (isReached ? ", reached" : ""))")
        .accessibilityAddTraits(.isButton)
    }
}
