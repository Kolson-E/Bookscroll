import QuartzCore
import SwiftUI
import UIKit

// X-style bars for the feed. While you read down, the navigation bar slides up (and fades) and
// the tab bar slides down, point for point with the content: they never move faster or slower
// than your finger. Scrolling up brings them back the same way. When a scroll stops part-way,
// the bars ease to the nearer end. At the top of the feed they always show. Scrolls the app
// makes itself (new posts above, Jump to) and layout changes of the feed do not move them.

/// The motion of the bars, with no UIKit in it, so tests can drive it.
struct ScrollChromeMotion: Equatable, Sendable {
    /// How far the navigation bar moves to hide: its height.
    private(set) var navigationDistance: CGFloat
    /// How far the tab bar moves to hide: its height and room for its shadow.
    private(set) var tabDistance: CGFloat
    /// How far the bars have moved away, in points: 0 is shown, `fullDistance` is hidden.
    /// Scrolling changes it point for point.
    private(set) var hidden: CGFloat = 0

    /// A larger change of the scroll position in one frame is a jump, not scrolling.
    static let largestStep: CGFloat = 250
    /// The ease to the nearer end: the remaining distance falls to 1/e in this time, so the
    /// bars get there in about a quarter of a second.
    static let settleTimeConstant: Double = 0.05
    /// The smallest step of the ease, so its end is not a long crawl.
    static let smallestSettleStep: CGFloat = 0.75
    /// Room under the tab bar for its shadow, so nothing of it shows when it is hidden.
    static let tabShadowRoom: CGFloat = 16

    init(navigationDistance: CGFloat = 44, tabDistance: CGFloat = 83 + ScrollChromeMotion.tabShadowRoom) {
        self.navigationDistance = max(0, navigationDistance)
        self.tabDistance = max(0, tabDistance)
    }

    var fullDistance: CGFloat { max(navigationDistance, tabDistance, 1) }
    var navigationOffset: CGFloat { min(hidden, navigationDistance) }
    var tabOffset: CGFloat { min(hidden, tabDistance) }
    var navigationAlpha: CGFloat { navigationDistance > 0 ? 1 - navigationOffset / navigationDistance : 1 }
    var isHidden: Bool { hidden >= fullDistance - 0.5 }
    var isShown: Bool { hidden <= 0.5 }

    /// New bar sizes (first layout, rotation, text size). Hidden bars stay hidden.
    mutating func setDistances(navigation: CGFloat, tab: CGFloat) {
        let wasHidden = isHidden && hidden > 0
        navigationDistance = max(0, navigation)
        tabDistance = max(0, tab)
        hidden = wasHidden ? fullDistance : min(hidden, fullDistance)
    }

    /// The content moved by `delta` points under the finger, or while it slows down after a
    /// flick (positive: reading down). Returns false for a jump, which does not count.
    @discardableResult
    mutating func scroll(by delta: CGFloat) -> Bool {
        guard delta.isFinite, abs(delta) <= Self.largestStep else { return false }
        hidden = min(fullDistance, max(0, hidden + delta))
        return true
    }

    /// Where the bars rest when a scroll stops: the nearer end, and always shown near the top.
    func restingPoint(distanceFromTop: CGFloat) -> CGFloat {
        if isShown || distanceFromTop < fullDistance { return 0 }
        if isHidden { return fullDistance }
        return hidden < fullDistance / 2 ? 0 : fullDistance
    }

    /// Moves `dt` seconds of the ease toward `target`. Returns true when the bars are there.
    @discardableResult
    mutating func settle(toward target: CGFloat, dt: Double) -> Bool {
        let goal = min(fullDistance, max(0, target))
        let remaining = goal - hidden
        if abs(remaining) <= 0.5 {
            hidden = goal
            return true
        }
        let time = dt.isFinite ? min(max(dt, 0), 0.1) : 0
        var step = remaining * CGFloat(1 - exp(-time / Self.settleTimeConstant))
        if abs(step) < Self.smallestSettleStep {
            step = (remaining < 0 ? -1 : 1) * min(Self.smallestSettleStep, abs(remaining))
        }
        hidden += step
        if abs(goal - hidden) <= 0.5 {
            hidden = goal
            return true
        }
        return false
    }

    /// Puts the bars at `value` points (tests, and showing them when the feed goes away).
    mutating func place(_ value: CGFloat) {
        hidden = value.isFinite ? min(fullDistance, max(0, value)) : 0
    }
}

/// What the bars did, for the UI tests: the app checks itself while the tests scroll.
struct ScrollChromeTrace: Equatable, Sendable {
    /// Frames that moved the bars.
    var frames = 0
    /// Frames where the tab bar moved more than the content did.
    var fasterThanContent = 0
    /// The fastest the tab bar moved while easing to an end, in points per second.
    var fastestEase: CGFloat = 0
    /// Times the bars rested shown but the tab bar was not back in its place.
    var notBackInPlace = 0
    /// Times the bars came to rest hidden, and shown.
    var restsHidden = 0
    var restsShown = 0
    /// Where the tab bar rests now: 0 shown, 1 hidden, 0.5 part-way.
    var restState: Double = 0
    /// How far the tab bar's content is moved down now, in points.
    var restOffset: CGFloat = 0
    /// 1 when the tab bar takes taps now.
    var restTaps = 1

    var summary: String {
        String(
            format: "frames=%d faster=%d ease=%.0f notBack=%d hidden=%d shown=%d state=%.1f offset=%.1f taps=%d",
            frames, fasterThanContent, Double(fastestEase), notBackInPlace, restsHidden, restsShown,
            restState, Double(restOffset), restTaps
        )
    }
}

/// Put it inside the scroll view's content; it finds the scroll view and the bars in UIKit.
@MainActor
struct ScrollChromeObserver: UIViewRepresentable {
    /// Off: the bars stay in place (VoiceOver, UI tests).
    var isEnabled: Bool
    /// UI tests only: the trace each time the bars come to rest.
    var onTrace: ((String) -> Void)?

    func makeUIView(context: Context) -> ScrollChromeView {
        ScrollChromeView()
    }

    func updateUIView(_ view: ScrollChromeView, context: Context) {
        view.onTrace = onTrace
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
            guard isEnabled != oldValue, !isEnabled else { return }
            stopEasing()
            motion.place(0)
            apply(input: nil)
        }
    }

    var onTrace: ((String) -> Void)?

    private(set) var motion = ScrollChromeMotion()
    private var trace = ScrollChromeTrace()

    private weak var scrollView: UIScrollView?
    private weak var navigationBar: UINavigationBar?
    private weak var tabBar: UITabBar?
    private var offsetObservation: NSKeyValueObservation?
    /// The content size at the last scroll position change: a change means the feed laid out
    /// posts, and that frame's movement is not the reader's.
    private var lastContentSize: CGSize = .zero
    /// The finger's position at the last pan update, in window points.
    private var lastFingerY: CGFloat = 0
    private var easeLink: CADisplayLink?
    private var easeTarget: CGFloat = 0
    private var restWork: DispatchWorkItem?
    /// Covers the status bar while the navigation bar is away, so posts do not show under
    /// the clock. The navigation bar slides under it.
    private var statusStrip: UIView?
    /// The bars' state as last applied, so only changes touch UIKit.
    private var appliedHidden: Bool?
    private var appliedStrip: Bool?

    private static let restDelay: TimeInterval = 0.08

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

    // MARK: Attach

    private func attach() {
        guard scrollView == nil else { return }
        var candidate = superview
        while let view = candidate, !(view is UIScrollView) { candidate = view.superview }
        guard let found = candidate as? UIScrollView else { return }
        scrollView = found
        lastContentSize = found.contentSize
        found.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        offsetObservation = found.observe(\.contentOffset, options: [.old, .new]) { [weak self] _, change in
            guard let old = change.oldValue?.y, let new = change.newValue?.y else { return }
            MainActor.assumeIsolated { self?.offsetChanged(from: old, to: new) }
        }
    }

    func detach() {
        restWork?.cancel()
        restWork = nil
        stopEasing()
        motion.place(0)
        apply(input: nil)
        offsetObservation?.invalidate()
        offsetObservation = nil
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        let hadBars = navigationBar != nil || tabBar != nil
        for bar in [navigationBar as UIView?, tabBar as UIView?].compactMap({ $0 }) { Self.reset(bar) }
        if hadBars { report() }
        scrollView = nil
        statusStrip?.removeFromSuperview()
        statusStrip = nil
        appliedStrip = nil
        appliedHidden = nil
        navigationBar = nil
        tabBar = nil
    }

    /// Finds the bars of the screen that holds the feed, and their sizes.
    /// Looked up again at each touch: UIKit can put new bars in place (after the Home Screen,
    /// for example), and a bar that is no longer the screen's bar goes back to normal.
    private func findBars() {
        if let start = sequence(first: self as UIResponder, next: { $0.next }).first(where: { $0 is UIViewController }) as? UIViewController {
            let controllers = Array(sequence(first: start, next: { $0.parent }))
            let foundNavigation = controllers.lazy.compactMap { ($0 as? UINavigationController) ?? $0.navigationController }.first?.navigationBar
            let foundTab = controllers.lazy.compactMap { ($0 as? UITabBarController) ?? $0.tabBarController }.first?.tabBar
            if let old = navigationBar, old !== foundNavigation { Self.reset(old) }
            if let old = tabBar, old !== foundTab { Self.reset(old) }
            if foundNavigation !== navigationBar || foundTab !== tabBar { appliedHidden = nil }
            navigationBar = foundNavigation
            tabBar = foundTab
        }
        motion.setDistances(
            navigation: navigationBar?.bounds.height ?? 0,
            tab: tabBar.map { $0.bounds.height + ScrollChromeMotion.tabShadowRoom } ?? 0
        )
    }

    /// A bar back in its place, visible and taking taps.
    private static func reset(_ bar: UIView) {
        bar.layer.sublayerTransform = CATransform3DIdentity
        bar.alpha = 1
        bar.accessibilityElementsHidden = false
        bar.isUserInteractionEnabled = true
    }

    /// Back from the Home Screen: the bars' state is set again from `motion`, in full.
    @objc private func appBecameActive() {
        guard scrollView != nil else { return }
        findBars()
        appliedHidden = nil
        appliedStrip = nil
        apply(input: nil)
        report()
    }

    // MARK: Scrolling

    private func topOffset(_ scrollView: UIScrollView) -> CGFloat {
        -scrollView.adjustedContentInset.top
    }

    private func bottomOffset(_ scrollView: UIScrollView) -> CGFloat {
        max(topOffset(scrollView), scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
    }

    /// Between the top and the end of the content, where the content moves with the finger
    /// (not in the bounce at either end).
    private func isInsideContent(_ offset: CGFloat, _ scrollView: UIScrollView) -> Bool {
        offset > topOffset(scrollView) + 0.5 && offset < bottomOffset(scrollView) - 0.5
    }

    /// Under the finger, the bars follow the finger itself, so layout changes of the feed
    /// during the drag do not move them.
    @objc private func panChanged(_ recognizer: UIPanGestureRecognizer) {
        guard isEnabled, let scrollView else { return }
        let fingerY = recognizer.translation(in: nil).y
        switch recognizer.state {
        case .began:
            stopEasing()
            restWork?.cancel()
            findBars()
            lastFingerY = fingerY
        case .changed:
            let delta = lastFingerY - fingerY
            lastFingerY = fingerY
            if isInsideContent(scrollView.contentOffset.y, scrollView), motion.scroll(by: delta) {
                apply(input: delta)
            }
        case .ended, .cancelled, .failed:
            scheduleRest()
        default:
            break
        }
    }

    private func offsetChanged(from old: CGFloat, to new: CGFloat) {
        guard isEnabled, let scrollView else { return }
        let size = scrollView.contentSize
        let laidOut = size != lastContentSize
        lastContentSize = size
        if new <= topOffset(scrollView) + 0.5 {
            // At the top (or pulled down to refresh): the bars show.
            restWork?.cancel()
            if !motion.isShown || easeLink != nil { ease(to: 0) }
            return
        }
        // The finger drives the bars while it is down (see `panChanged`).
        guard !scrollView.isTracking else { return }
        guard scrollView.isDecelerating else { return }
        // After a flick: the content's own movement, without layout jumps or the bounce.
        if easeLink == nil, !laidOut, isInsideContent(old, scrollView), isInsideContent(new, scrollView),
           motion.scroll(by: new - old) {
            apply(input: new - old)
        }
        scheduleRest()
    }

    /// When the scroll has stopped and the finger is up, the bars ease to the nearer end.
    private func scheduleRest() {
        restWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.restIfStopped() }
        }
        restWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restDelay, execute: work)
    }

    private func restIfStopped() {
        guard isEnabled, let scrollView, !scrollView.isTracking else { return }
        if scrollView.isDecelerating {
            scheduleRest()
            return
        }
        let fromTop = scrollView.contentOffset.y - topOffset(scrollView)
        ease(to: motion.restingPoint(distanceFromTop: fromTop))
    }

    // MARK: Easing

    private func ease(to target: CGFloat) {
        easeTarget = target
        if abs(motion.hidden - target) <= 0.5 {
            stopEasing()
            motion.place(target)
            apply(input: nil)
            didRest()
            return
        }
        guard easeLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(easeFrame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        easeLink = link
    }

    @objc private func easeFrame(_ link: CADisplayLink) {
        let dt = link.targetTimestamp - link.timestamp
        let before = motion.tabOffset
        let done = motion.settle(toward: easeTarget, dt: dt)
        apply(input: nil)
        if onTrace != nil, dt > 0 {
            trace.fastestEase = max(trace.fastestEase, abs(motion.tabOffset - before) / CGFloat(dt))
        }
        if done {
            stopEasing()
            didRest()
        }
    }

    private func stopEasing() {
        easeLink?.invalidate()
        easeLink = nil
    }

    private func didRest() {
        guard onTrace != nil else { return }
        if motion.isShown {
            trace.restsShown += 1
            if let tabBar, tabBar.layer.sublayerTransform.m42 != 0 || !tabBar.transform.isIdentity || tabBar.alpha != 1 {
                trace.notBackInPlace += 1
            }
        } else if motion.isHidden {
            trace.restsHidden += 1
        }
        report()
    }

    /// Tells the UI tests where the tab bar is now (only when they ask for it).
    private func report() {
        guard onTrace != nil else { return }
        trace.restState = motion.isShown ? 0 : motion.isHidden ? 1 : 0.5
        trace.restOffset = tabBar?.layer.sublayerTransform.m42 ?? 0
        trace.restTaps = tabBar?.isUserInteractionEnabled == false ? 0 : 1
        let summary = trace.summary
        // Not inside a SwiftUI update.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onTrace?(summary) }
        }
    }

    // MARK: Applying

    /// Puts the bars where `motion` says. The bars move by their layers' sublayer transform,
    /// which UIKit's own layout of the bars never sets, so a layout pass cannot move them.
    /// `input` is the content's movement in this frame, for the trace.
    private func apply(input: CGFloat?) {
        let tabBefore = tabBar?.layer.sublayerTransform.m42 ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let navigationBar {
            let offset = motion.navigationOffset
            navigationBar.layer.sublayerTransform = offset == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(0, -offset, 0)
            navigationBar.alpha = motion.navigationAlpha
        }
        if let tabBar {
            let offset = motion.tabOffset
            tabBar.layer.sublayerTransform = offset == 0 ? CATransform3DIdentity : CATransform3DMakeTranslation(0, offset, 0)
        }
        CATransaction.commit()

        let showsStrip = !motion.isShown
        if appliedStrip != showsStrip {
            appliedStrip = showsStrip
            if showsStrip { placeStatusStrip() }
            statusStrip?.alpha = showsStrip ? 1 : 0
        }
        let hidden = motion.isHidden
        if appliedHidden != hidden {
            appliedHidden = hidden
            for bar in [navigationBar as UIView?, tabBar as UIView?].compactMap({ $0 }) {
                bar.accessibilityElementsHidden = hidden
                bar.isUserInteractionEnabled = !hidden
            }
            // The bars' buttons came or went: assistive apps (and UI tests) read the screen again.
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }

        if onTrace != nil, let input, let tabBar {
            trace.frames += 1
            let moved = abs(tabBar.layer.sublayerTransform.m42 - tabBefore)
            if moved > abs(input) + 0.5 { trace.fasterThanContent += 1 }
        }
    }

    private func placeStatusStrip() {
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
        strip.frame = CGRect(x: 0, y: 0, width: host.bounds.width, height: max(0, navigationBar.frame.minY))
        strip.backgroundColor = UIColor(Theme.background)
    }
}
