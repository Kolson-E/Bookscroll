import PhotosUI
import SwiftUI

/// Edit Details: the title and author the app shows, the avatar (the book's cover, a photo
/// the reader picks, or the initial on the book's colour) and facts about the file.
/// Nothing changes until Save.
@MainActor
struct BookDetailsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let bookID: UUID

    @State private var loaded = false
    @State private var title = ""
    @State private var author = ""
    @State private var showsCover = true
    @State private var cover: UIImage?
    @State private var savedPhoto: UIImage?
    @State private var removesSavedPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var newPhotoData: Data?
    @State private var newPhoto: UIImage?
    @State private var photoError: String?
    @State private var isPickingReplacement = false
    @ScaledMetric(relativeTo: .largeTitle) private var previewSize: CGFloat = 96

    private var book: Book? { app.store.book(id: bookID) }

    private var currentPhoto: UIImage? {
        newPhoto ?? (removesSavedPhoto ? nil : savedPhoto)
    }

    private var previewImage: UIImage? {
        showsCover ? (currentPhoto ?? cover) : nil
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Group {
                if let book {
                    form(book)
                } else {
                    ContentUnavailableView("Book not found", systemImage: "book.closed")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .themedNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("details.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { _ = save() }
                        .fontWeight(.semibold)
                        .disabled(trimmedTitle.isEmpty || book == nil)
                        .accessibilityIdentifier("details.save")
                }
            }
        }
        .tint(Theme.accent)
        .fileImporter(isPresented: $isPickingReplacement, allowedContentTypes: BookFormat.importableTypes) { result in
            guard case let .success(url) = result, save() else { return }
            app.replaceFile(of: bookID, with: url)
        }
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    private func form(_ book: Book) -> some View {
        Form {
            Section {
                AvatarView(title: trimmedTitle.isEmpty ? book.title : trimmedTitle, author: author, size: min(previewSize, 160), textStyle: .largeTitle, image: previewImage)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityElement()
                    .accessibilityLabel(previewDescription)
                    .accessibilityIdentifier("details.avatar")
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label {
                        Text(currentPhoto == nil ? "Choose Photo\u{2026}" : "Choose Another Photo\u{2026}")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        Image(systemName: "photo")
                    }
                }
                .accessibilityIdentifier("details.photo")
                if currentPhoto != nil {
                    Button(role: .destructive) {
                        newPhoto = nil
                        newPhotoData = nil
                        photoItem = nil
                        removesSavedPhoto = savedPhoto != nil
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                    .accessibilityIdentifier("details.photo.remove")
                }
                if let photoError {
                    Label(photoError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Toggle(isOn: $showsCover) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Cover or Photo")
                            .foregroundStyle(Theme.primaryText)
                        Text("Off shows the first letter of the title.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityIdentifier("details.showsCover")
            } header: {
                SectionHeader("Avatar")
            }
            .listRowBackground(Theme.secondaryBackground)

            Section {
                TextField("Title", text: $title, axis: .vertical)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityLabel("Title")
                    .accessibilityIdentifier("details.title")
                TextField("Author", text: $author, axis: .vertical)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityLabel("Author")
                    .accessibilityIdentifier("details.author")
            } header: {
                SectionHeader("Shown as")
            }
            .listRowBackground(Theme.secondaryBackground)

            Section {
                DetailRow(title: "Format", value: book.format.label)
                if let name = book.sourceFileName {
                    DetailRow(title: "File", value: name)
                }
                if book.sourceFileSize > 0 {
                    DetailRow(title: "File size", value: Int64(book.sourceFileSize).formatted(.byteCount(style: .file)))
                }
                DetailRow(title: "Language", value: languageName(book.language))
                DetailRow(title: "Added", value: book.addedAt.formatted(date: .abbreviated, time: .omitted))
                if let lastReadAt = book.lastReadAt {
                    DetailRow(title: "Last read", value: lastReadAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let finishedAt = book.finishedAt {
                    DetailRow(title: "Finished", value: finishedAt.formatted(date: .abbreviated, time: .omitted))
                }
                Button("Replace File\u{2026}") { isPickingReplacement = true }
                    .frame(minHeight: 44)
                    .accessibilityHint("Imports a new version of this book and keeps your place, marks and shelves")
                    .accessibilityIdentifier("details.replaceFile")
            } header: {
                SectionHeader("About the file")
            } footer: {
                Text("Replace File imports a new version of the book, such as a corrected EPUB. Your place, likes, bookmarks, highlights, shelves and the details above move to the new version; where its text changed, they go to the nearest matching words.")
                    .foregroundStyle(Theme.secondaryText)
            }
            .listRowBackground(Theme.secondaryBackground)
        }
    }

    private var previewDescription: String {
        if !showsCover || previewImage == nil { return "Avatar: the first letter of the title" }
        return currentPhoto != nil ? "Avatar: your photo" : "Avatar: the book cover"
    }

    private func languageName(_ code: String?) -> String {
        guard let code else { return "Not detected" }
        return Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func load() {
        guard !loaded, let book else { return }
        loaded = true
        title = book.title
        author = book.author
        showsCover = book.showsCover
        let folder = CoverCache.shared.folder
        cover = (try? Data(contentsOf: CoverStore.url(bookID: bookID, photo: false, in: folder))).flatMap(UIImage.init(data:))
        savedPhoto = (try? Data(contentsOf: CoverStore.url(bookID: bookID, photo: true, in: folder))).flatMap(UIImage.init(data:))
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        photoError = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = CoverStore.thumbnailJPEG(from: data),
              let image = UIImage(data: jpeg) else {
            photoError = "This photo could not be opened."
            return
        }
        newPhotoData = jpeg
        newPhoto = image
        showsCover = true
    }

    /// Applies the changes and closes the sheet. False when the photo could not be saved.
    private func save() -> Bool {
        guard book != nil else { return false }
        if let newPhotoData {
            if !app.setAvatarPhoto(bookID: bookID, data: newPhotoData) {
                photoError = "The photo could not be saved."
                return false
            }
        } else if removesSavedPhoto {
            app.removeAvatarPhoto(bookID: bookID)
        }
        app.setShowsCover(showsCover, bookID: bookID)
        app.editDetails(bookID: bookID, title: title, author: author)
        dismiss()
        return true
    }
}

/// A label and its value in the theme's colours. The value wraps under the label when the
/// text is large.
@MainActor
private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Theme.primaryText)
                Spacer(minLength: 12)
                Text(value)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.primaryText)
                Text(value)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
