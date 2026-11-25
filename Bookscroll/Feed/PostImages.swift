import SwiftUI
import UIKit

/// The pictures under a post's text, as on X: full width with rounded corners. A tall
/// picture is cut to 4:5 (the full picture opens with a tap). Tapping a picture opens the
/// full-screen viewer.
@MainActor
struct PostImages: View {
    let bookID: UUID
    let images: [BookImageEntry]
    /// The post the pictures belong to, shown under the picture full screen. Nil in the reader.
    var post: ViewerPost? = nil

    @State private var viewing: ViewerStart?

    private struct ViewerStart: Identifiable {
        let id = UUID()
        let index: Int
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(images.enumerated()), id: \.element) { index, entry in
                Button {
                    open(at: index)
                } label: {
                    PostImageTile(bookID: bookID, entry: entry)
                }
                .buttonStyle(PictureButtonStyle())
                .accessibilityLabel(entry.alt.isEmpty ? Text("Picture") : Text("Picture: \(entry.alt)"))
                .accessibilityAddTraits(.isImage)
                .accessibilityHint("Opens the picture full screen")
                .accessibilityIdentifier("post.image")
            }
        }
        .fullScreenCover(item: $viewing) { start in
            ImageViewer(bookID: bookID, images: images, startIndex: start.index, post: post) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { viewing = nil }
            }
        }
    }

    /// The viewer comes in by its own fade, not the sheet's slide.
    private func open(at index: Int) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { viewing = ViewerStart(index: index) }
    }
}

/// No dimming on press: the viewer opens at once.
private struct PictureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
    }
}

/// One picture in a post. Its height is known before the picture loads, so the feed never
/// jumps while it scrolls.
@MainActor
struct PostImageTile: View {
    let bookID: UUID
    let entry: BookImageEntry

    /// Pixels on the longest side for the feed: the width of the largest phone screen.
    static let feedPixels = 1400
    /// Taller pictures are cut to this height (4:5), as on X.
    static let tallestAspectRatio: CGFloat = 1.25
    static let cornerRadius: CGFloat = 16

    @State private var image: UIImage?

    private var shownAspectRatio: CGFloat {
        min(max(entry.aspectRatio, 0.2), Self.tallestAspectRatio)
    }

    var body: some View {
        Color.clear
            .aspectRatio(1 / shownAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Theme.secondaryBackground)
            .overlay {
                if let image = image ?? BookImageCache.shared.cachedImage(entry, bookID: bookID, pixels: Self.feedPixels) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            }
            .task(id: entry) {
                guard image == nil else { return }
                image = await BookImageCache.shared.image(entry, bookID: bookID, pixels: Self.feedPixels)
            }
    }
}

/// The post a picture belongs to, for the viewer's post panel (as on X's media viewer).
@MainActor
struct ViewerPost {
    let bookID: UUID
    let title: String
    let author: String
    let text: String
    let citation: String
    let isBookmarked: Bool
    let actions: PostActions

    init(post: FeedPost, isBookmarked: Bool, actions: PostActions) {
        bookID = post.bookID
        title = post.bookTitle
        author = post.bookAuthor
        text = post.segment.text
        citation = ShareFormatter.citation(post)
        self.isBookmarked = isBookmarked
        self.actions = actions
    }
}

/// A book's pictures full screen, as on X's media viewer: black behind, a back button and "⋯"
/// at the top, and the post under the picture with its actions as capsules. There is no reply
/// field: nothing in the app takes replies. Pinch or double-tap to zoom, swipe sideways between
/// the post's pictures, swipe up or down to close. A tap shows or hides everything but the picture.
@MainActor
struct ImageViewer: View {
    let bookID: UUID
    let images: [BookImageEntry]
    /// Nil in the reader, where a paragraph is not a post: the panel shows the description only.
    let post: ViewerPost?
    let onClose: () -> Void

    @State private var index: Int
    @State private var appeared = false
    @State private var closing = false
    /// 0 at rest, 1 when a swipe has taken the picture away.
    @State private var dragProgress: CGFloat = 0
    @State private var showsControls = true
    /// The picture's description, opened with the "ALT" button.
    @State private var showsAlt = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(bookID: UUID, images: [BookImageEntry], startIndex: Int, post: ViewerPost? = nil, onClose: @escaping () -> Void) {
        self.bookID = bookID
        self.images = images
        self.post = post
        self.onClose = onClose
        _index = State(initialValue: min(max(startIndex, 0), max(images.count - 1, 0)))
    }

    private var backgroundOpacity: Double {
        guard appeared, !closing else { return 0 }
        return Double(1 - min(dragProgress, 1) * 0.85)
    }

    private var controlsOpacity: Double {
        appeared && !closing ? Double(1 - min(dragProgress * 2, 1)) : 0
    }

    private var entry: BookImageEntry? { images[safe: index] }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(images.enumerated()), id: \.element) { n, entry in
                    ZoomableImage(
                        bookID: bookID,
                        entry: entry,
                        onDragProgress: { dragProgress = $0 },
                        onSwipedAway: finishClosing,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() }
                        }
                    )
                    .ignoresSafeArea()
                    .tag(n)
                    .accessibilityElement()
                    .accessibilityLabel(entry.alt.isEmpty ? Text("Picture") : Text("Picture: \(entry.alt)"))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("imageViewer.image")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            .ignoresSafeArea()
            .opacity(appeared && !closing ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)

            if showsControls {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomPanel
                }
                .opacity(controlsOpacity)
                .transition(.opacity)
            }
        }
        .presentationBackground(.clear)
        .statusBarHidden()
        .accessibilityAction(.escape) { close() }
        .onChange(of: index) { showsAlt = false }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.22)) { appeared = true }
        }
    }

    // MARK: Top: back, page count, more

    private var topBar: some View {
        HStack {
            Button { close() } label: {
                ViewerCircleIcon(systemName: "arrow.left")
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("imageViewer.close")
            Spacer()
            if images.count > 1 {
                Text("\(index + 1) of \(images.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(viewerChromeFill))
                Spacer()
            }
            Menu {
                if post != nil {
                    Button { readInContext() } label: {
                        Label("Read in context", systemImage: "text.book.closed")
                    }
                    Button { post?.actions.copy(true) } label: {
                        Label("Copy text with citation", systemImage: "doc.on.doc")
                    }
                }
                Button(action: copyPicture) {
                    Label("Copy picture", systemImage: "photo.on.rectangle")
                }
            } label: {
                ViewerCircleIcon(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("imageViewer.more")
        }
        .padding(.horizontal, 8)
    }

    // MARK: Bottom: the post and its actions

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let alt = entry?.alt, !alt.isEmpty, showsAlt || post == nil {
                Text(alt)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
            if let post {
                Button { readInContext() } label: {
                    postSummary(post)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "\(post.title), \(post.author). \(post.text)"))
                .accessibilityHint("Reads the post in context")
                .accessibilityIdentifier("imageViewer.post")
            }
            actionRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 40)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.black.opacity(0), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    /// Avatar, bold title and grey author, then the text cut to two lines: X's post under the media.
    private func postSummary(_ post: ViewerPost) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(title: post.title, author: post.author, size: 40, textStyle: .title3, bookID: post.bookID)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(post.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(post.author)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
                Text(post.text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            if let post {
                Button { readInContext() } label: {
                    ViewerCapsule {
                        Label("Read", systemImage: "text.book.closed")
                    }
                }
                .accessibilityLabel("Read in context")
                .accessibilityIdentifier("imageViewer.context")

                Button(action: post.actions.bookmark) {
                    ViewerCapsule {
                        Image(systemName: post.isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                }
                .accessibilityLabel(post.isBookmarked ? "Remove bookmark" : "Bookmark")
                .accessibilityIdentifier("imageViewer.bookmark")
            }
            if let entry {
                let file = BookImageCache.shared.url(of: entry, bookID: bookID)
                Group {
                    if let post {
                        ShareLink(item: file, message: Text(post.citation)) {
                            ViewerCapsule { Image(systemName: "square.and.arrow.up") }
                        }
                    } else {
                        ShareLink(item: file) {
                            ViewerCapsule { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                }
                .accessibilityLabel("Share picture")
                .accessibilityIdentifier("imageViewer.share")
            }
            Spacer(minLength: 0)
            if post != nil, let alt = entry?.alt, !alt.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showsAlt.toggle() }
                } label: {
                    ViewerCapsule {
                        Text("ALT").font(.caption.weight(.heavy))
                    }
                }
                .accessibilityLabel(showsAlt ? "Hide picture description" : "Show picture description")
                .accessibilityIdentifier("imageViewer.alt")
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Closing

    /// "Read in context": the reader opens over the feed once the viewer has gone, since a
    /// sheet cannot open over this cover.
    private func readInContext() {
        guard let open = post?.actions.open else { return }
        close(then: open)
    }

    private func copyPicture() {
        guard let entry else { return }
        Task {
            if let image = await BookImageCache.shared.image(entry, bookID: bookID, pixels: max(entry.width, entry.height)) {
                UIPasteboard.general.image = image
            }
        }
    }

    /// The back button and VoiceOver's escape: a short fade, then the cover goes.
    private func close(then next: (() -> Void)? = nil) {
        guard !closing else { return }
        withAnimation(.easeIn(duration: 0.18)) { closing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onClose()
            if let next {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: next)
            }
        }
    }

    /// The picture has already slid away.
    private func finishClosing() {
        guard !closing else { return }
        withAnimation(.easeOut(duration: 0.12)) { closing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { onClose() }
    }
}

/// The see-through fill of the viewer's capsules.
private let viewerChromeFill = Color.white.opacity(0.16)

/// X's round buttons at the top of the media viewer.
private struct ViewerCircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// X's action capsules under the post in the media viewer.
private struct ViewerCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minWidth: 52, minHeight: 36)
            .background(Capsule().fill(viewerChromeFill))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// One picture in the viewer: a zooming scroll view, with a swipe to close while the picture
/// is not zoomed.
private struct ZoomableImage: UIViewRepresentable {
    let bookID: UUID
    let entry: BookImageEntry
    let onDragProgress: (CGFloat) -> Void
    let onSwipedAway: () -> Void
    let onTap: () -> Void

    func makeUIView(context: Context) -> ZoomingImageView {
        let view = ZoomingImageView()
        view.aspectRatio = entry.aspectRatio
        view.image = BookImageCache.shared.cachedImage(entry, bookID: bookID, pixels: PostImageTile.feedPixels)
        let pixels = max(entry.width, entry.height)
        Task { @MainActor [weak view] in
            if view?.image == nil {
                view?.image = await BookImageCache.shared.image(entry, bookID: bookID, pixels: PostImageTile.feedPixels)
            }
            // Then the full picture, for zooming.
            if pixels > PostImageTile.feedPixels, let full = await BookImageCache.shared.image(entry, bookID: bookID, pixels: pixels) {
                view?.image = full
            }
        }
        return view
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.onDragProgress = onDragProgress
        view.onSwipedAway = onSwipedAway
        view.onTap = onTap
    }
}

/// A scroll view that zooms one picture (pinch, or double-tap), and moves it with a vertical
/// swipe while it is not zoomed: far or fast enough closes the viewer, else it springs back.
final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    var onDragProgress: ((CGFloat) -> Void)?
    var onSwipedAway: (() -> Void)?
    var onTap: (() -> Void)?
    /// Height divided by width, known before the picture loads.
    var aspectRatio: CGFloat = 1 {
        didSet { setNeedsLayout() }
    }

    var image: UIImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            setNeedsLayout()
        }
    }

    private let imageView = UIImageView()
    private let swipe = UIPanGestureRecognizer()
    /// The swipe's delegate is its own object: the scroll view is already the delegate of its
    /// own gestures, and its methods must not be replaced.
    private let swipeDelegate = SwipeDelegate()
    private var laidOutSize: CGSize = .zero

    /// Distance and speed that close the viewer.
    private static let closeDistance: CGFloat = 110
    private static let closeSpeed: CGFloat = 900

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        decelerationRate = .fast
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        swipe.addTarget(self, action: #selector(swiped(_:)))
        swipeDelegate.shouldBegin = { [weak self] in self?.swipeShouldBegin() ?? false }
        swipe.delegate = swipeDelegate
        addGestureRecognizer(swipe)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize || imageView.frame.isEmpty else {
            centerImage()
            return
        }
        laidOutSize = bounds.size
        zoomScale = 1
        let ratio = image.map { $0.size.width > 0 ? $0.size.height / $0.size.width : aspectRatio } ?? aspectRatio
        var size = CGSize(width: bounds.width, height: bounds.width * ratio)
        if size.height > bounds.height, ratio > 0 {
            size = CGSize(width: bounds.height / ratio, height: bounds.height)
        }
        imageView.transform = .identity
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerImage()
    }

    /// Keeps a picture smaller than the screen in the middle.
    private func centerImage() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    @objc private func singleTapped() {
        onTap?()
    }

    @objc private func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = recognizer.location(in: imageView)
            let scale = min(maximumZoomScale, 2.5)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }

    // MARK: Swipe to close

    /// Only a mostly vertical swipe of a picture that is not zoomed.
    private func swipeShouldBegin() -> Bool {
        guard zoomScale <= minimumZoomScale + 0.01 else { return false }
        let velocity = swipe.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x)
    }

    @objc private func swiped(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .changed:
            imageView.transform = CGAffineTransform(translationX: translation.x * 0.4, y: translation.y)
            onDragProgress?(min(1, abs(translation.y) / 300))
        case .ended, .cancelled, .failed:
            let velocity = recognizer.velocity(in: self).y
            let away = recognizer.state == .ended
                && (abs(translation.y) > Self.closeDistance || abs(velocity) > Self.closeSpeed)
                && (translation.y == 0 || velocity == 0 || (translation.y > 0) == (velocity > 0) || abs(translation.y) > Self.closeDistance * 2)
            if away {
                let direction: CGFloat = (abs(velocity) > Self.closeSpeed ? velocity : translation.y) >= 0 ? 1 : -1
                let distance = bounds.height
                let speed = max(abs(velocity), 1600)
                UIView.animate(withDuration: min(0.3, Double(distance / speed)), delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                    self.imageView.transform = CGAffineTransform(translationX: translation.x * 0.4, y: direction * distance)
                }
                onDragProgress?(1)
                onSwipedAway?()
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.imageView.transform = .identity
                }
                onDragProgress?(0)
            }
        default:
            break
        }
    }
}

/// Lets the swipe to close begin only when it should, alongside the scroll views' own pans.
@MainActor
private final class SwipeDelegate: NSObject, UIGestureRecognizerDelegate {
    var shouldBegin: (() -> Bool)?

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        shouldBegin?() ?? false
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer
    }
}
