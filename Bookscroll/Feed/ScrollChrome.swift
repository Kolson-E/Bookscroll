import SwiftUI
import UIKit

/// X-style bars for the feed. While you read down, the navigation bar slides up and fades,
/// and the tab bar slides down and fades, in step with your finger. Scrolling up brings them
/// back the same way. When a scroll stops part-way, the bars go to the nearer end. At the top
/// of the feed they always show. Scrolls the app makes itself (new posts above, Jump to) do
/// not move them.
///
/// Put it inside the scroll view's content; it finds the scroll view and the bars in UIKit.
@MainActor
struct ScrollChromeObserver: UIViewRepresentable {
    /// Off: the bars stay in place (VoiceOver, UI tests).
    var isEnabled: Bool

    func makeUIView(context: Context) -> ScrollChromeView {
        ScrollChromeView()
    }

    func updateUIView(_ view: ScrollChromeView, context: Context) {
        view.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: ScrollChromeView, coordinator: ()) {
        view.detach()
    }
}

@MainActor
final class ScrollChromeView: UIView {
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { setProgress(0, animated: true) }
        }
    }

    /// 0 is bars fully shown, 1 is bars fully hidden.
    private(set) var progress: CGFloat = 0

    private weak var scrollView: UIScrollView?
    private weak var navigationBar: UINavigationBar?
    private weak var tabBar: UITabBar?
    private var observation: NSKeyValueObservation?
    /// Covers the status bar while the navigation bar is away, so posts do not show under
    /// the clock. The navigation bar slides under it.
    private var statusStrip: UIView?
    private var snapWork: DispatchWorkItem?

    /// Offset changes larger than this in one step are jumps, not scrolling.
    private static let largestStep: CGFloat = 400
    private static let snapDelay: TimeInterval = 0.12

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // Another tab, or the feed went away: the shared tab bar must come back.
            detach()
        } else {
            attach()
        }
    }

    private func attach() {
        guard scrollView == nil else { return }
        var candidate = superview
        while let view = candidate, !(view is UIScrollView) { candidate = view.superview }
        guard let found = candidate as? UIScrollView else { return }
        scrollView = found
        found.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        observation = found.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
            guard let old = change.oldValue?.y, let new = change.newValue?.y else { return }
            MainActor.assumeIsolated { self?.offsetChanged(from: old, to: new) }
        }
    }

    func detach() {
        snapWork?.cancel()
        snapWork = nil
        setProgress(0, animated: false)
        observation?.invalidate()
        observation = nil
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
        scrollView = nil
        statusStrip?.removeFromSuperview()
        statusStrip = nil
        navigationBar = nil
        tabBar = nil
    }

    /// Finds the bars of the screen that holds the feed.
    private func findBars() {
        guard navigationBar == nil || tabBar == nil else { return }
        guard let start = sequence(first: self as UIResponder, next: { $0.next }).first(where: { $0 is UIViewController }) as? UIViewController else { return }
        let controllers = Array(sequence(first: start, next: { $0.parent }))
        if navigationBar == nil {
            navigationBar = controllers.lazy.compactMap { ($0 as? UINavigationController) ?? $0.navigationController }.first?.navigationBar
        }
        if tabBar == nil {
            tabBar = controllers.lazy.compactMap { ($0 as? UITabBarController) ?? $0.tabBarController }.first?.tabBar
        }
    }

    /// The scroll distance that hides the bars: the navigation bar's height, as on X.
    private var distance: CGFloat { max(44, navigationBar?.bounds.height ?? 44) }

    private func offsetChanged(from old: CGFloat, to new: CGFloat) {
        guard isEnabled, let scrollView else { return }
        findBars()
        let top = -scrollView.adjustedContentInset.top
        if new <= top + 1 {
            // At the top (or pulled down to refresh): the bars show.
            snapWork?.cancel()
            if progress > 0 { setProgress(0, animated: !scrollView.isTracking) }
            return
        }
        guard scrollView.isTracking || scrollView.isDecelerating else { return }
        let bottom = max(top, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        let delta = new - old
        // The bounce at the end of the content does not count.
        if new < bottom, old < bottom, abs(delta) < Self.largestStep {
            setProgress(progress + delta / distance, animated: false)
        }
        scheduleSnap()
    }

    @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            scheduleSnap()
        }
    }

    /// When the scroll has stopped and the finger is up, the bars go to the nearer end.
    private func scheduleSnap() {
        snapWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.snapIfStopped() }
        }
        snapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.snapDelay, execute: work)
    }

    private func snapIfStopped() {
        guard let scrollView, !scrollView.isTracking, !scrollView.isDecelerating else { return }
        guard progress > 0, progress < 1 else { return }
        let fromTop = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        setProgress(progress < 0.5 || fromTop < distance ? 0 : 1, animated: true)
    }

    private func setProgress(_ value: CGFloat, animated: Bool) {
        let clamped = min(1, max(0, value))
        guard clamped != progress || !animated else { return }
        progress = clamped
        if clamped > 0 { addStatusStrip() }
        let apply = { [self] in
            if let navigationBar {
                navigationBar.transform = clamped == 0 ? .identity : CGAffineTransform(translationX: 0, y: -navigationBar.bounds.height * clamped)
                navigationBar.alpha = 1 - clamped
            }
            if let tabBar {
                tabBar.transform = clamped == 0 ? .identity : CGAffineTransform(translationX: 0, y: tabBar.bounds.height * clamped)
                tabBar.alpha = 1 - clamped
            }
            statusStrip?.alpha = clamped > 0 ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut], animations: apply)
        } else {
            apply()
        }
        let hidden = clamped >= 1
        for bar in [navigationBar as UIView?, tabBar as UIView?].compactMap({ $0 }) {
            bar.accessibilityElementsHidden = hidden
            bar.isUserInteractionEnabled = !hidden
        }
    }

    private func addStatusStrip() {
        guard let navigationBar, let host = navigationBar.superview else { return }
        let strip = statusStrip ?? {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.autoresizingMask = [.flexibleWidth]
            view.alpha = 0
            statusStrip = view
            return view
        }()
        if strip.superview !== host {
            host.insertSubview(strip, aboveSubview: navigationBar)
        }
        strip.frame = CGRect(x: 0, y: 0, width: host.bounds.width, height: max(0, navigationBar.center.y - navigationBar.bounds.height / 2))
        strip.backgroundColor = UIColor(Theme.background)
    }
}
