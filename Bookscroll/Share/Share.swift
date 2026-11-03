import SwiftUI
import UIKit

enum ShareFormatter {
    /// The post text in quotes, followed by "Title by Author".
    static func quote(text: String, title: String, author: String) -> String {
        "\u{201C}\(text)\u{201D}\n\n\(title) by \(author)"
    }

    static func quote(_ post: FeedPost) -> String {
        quote(text: post.segment.text, title: post.bookTitle, author: post.bookAuthor)
    }
}

/// The post as an image card, for sharing.
@MainActor
struct ShareCardView: View {
    let post: FeedPost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(title: post.bookTitle, author: post.bookAuthor, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.bookTitle)
                        .font(.headline)
                        .foregroundStyle(.black)
                    Text(post.bookAuthor)
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
            }
            Text(post.segment.text)
                .font(.system(size: 19, design: .serif))
                .foregroundStyle(.black)
                .lineLimit(24)
                .fixedSize(horizontal: false, vertical: true)
            if !post.segment.chapter.isEmpty {
                Text(post.segment.chapter)
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }
        }
        .padding(28)
        .frame(width: 390, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }
}

@MainActor
enum ShareCardRenderer {
    static func image(for post: FeedPost) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(post: post))
        renderer.scale = 3
        return renderer.uiImage
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
